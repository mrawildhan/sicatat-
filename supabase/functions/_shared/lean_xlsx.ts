// A small .xlsx reader for large Ellipse/warehouse workbooks. SheetJS needs
// about 1.5 s of CPU for a 20 000-row workbook, close to the Edge Function CPU
// limit; this reader only unzips the requested sheets and scans their XML.
// Cells come back as text (shared/inline strings) or numbers (everything
// else, including Excel date serials).

import { strFromU8, unzipSync } from "npm:fflate@0.8.2";

export type Cell = string | number | null;
export type SheetRows = Cell[][];

const entities: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&apos;": "'",
};

function decode(value: string): string {
  if (!value.includes("&")) return value;
  return value.replace(/&(amp|lt|gt|quot|apos);|&#(\d+);|&#x([0-9a-fA-F]+);/g, (match, _name, dec, hex) => {
    if (dec) return String.fromCodePoint(Number(dec));
    if (hex) return String.fromCodePoint(parseInt(hex, 16));
    return entities[match] ?? match;
  });
}

function textOf(xml: string): string {
  let result = "";
  const re = /<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g;
  for (let m = re.exec(xml); m; m = re.exec(xml)) result += m[1];
  return decode(result);
}

function columnIndex(letters: string): number {
  let index = 0;
  for (let i = 0; i < letters.length; i++) index = index * 26 + (letters.charCodeAt(i) - 64);
  return index - 1;
}

/** Sheet names in workbook order, mapped to their XML part paths. */
function sheetPaths(files: Record<string, Uint8Array>): Map<string, string> {
  const workbook = strFromU8(files["xl/workbook.xml"]);
  const rels = strFromU8(files["xl/_rels/workbook.xml.rels"]);
  const targets = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) {
    const id = /\bId="([^"]+)"/.exec(m[0])?.[1];
    const target = /\bTarget="([^"]+)"/.exec(m[0])?.[1];
    if (id && target) {
      targets.set(id, target.startsWith("/") ? target.slice(1) : `xl/${target}`);
    }
  }
  const result = new Map<string, string>();
  for (const m of workbook.matchAll(/<sheet\b[^>]*>/g)) {
    const name = /\bname="([^"]+)"/.exec(m[0])?.[1];
    const rid = /\br:id="([^"]+)"/.exec(m[0])?.[1];
    const path = rid ? targets.get(rid) : undefined;
    if (name && path) result.set(decode(name), path);
  }
  return result;
}

function sharedStrings(xml: string | undefined): string[] {
  if (!xml) return [];
  const result: string[] = [];
  const re = /<si>([\s\S]*?)<\/si>/g;
  for (let m = re.exec(xml); m; m = re.exec(xml)) result.push(textOf(m[1]));
  return result;
}

function parseSheet(xml: string, strings: string[], maxColumns: number): SheetRows {
  const rows: SheetRows = [];
  const rowRe = /<row\b[^>]*?\br="(\d+)"[^>]*?(?:\/>|>([\s\S]*?)<\/row>)/g;
  const cellRe = /<c\b[^>]*?\br="([A-Z]+)\d+"([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
  for (let row = rowRe.exec(xml); row; row = rowRe.exec(xml)) {
    const rowIndex = Number(row[1]) - 1;
    const values: Cell[] = [];
    const body = row[2] ?? "";
    cellRe.lastIndex = 0;
    for (let cell = cellRe.exec(body); cell; cell = cellRe.exec(body)) {
      const column = columnIndex(cell[1]);
      if (column >= maxColumns) continue;
      const inner = cell[3];
      if (inner === undefined) continue;
      const type = /\bt="([^"]+)"/.exec(cell[2])?.[1];
      let value: Cell = null;
      if (type === "inlineStr") {
        value = textOf(inner);
      } else {
        const raw = /<v>([\s\S]*?)<\/v>/.exec(inner)?.[1];
        if (raw === undefined) continue;
        if (type === "s") value = strings[Number(raw)] ?? null;
        else if (type === "str" || type === "e") value = decode(raw);
        else if (type === "b") value = raw === "1" ? 1 : 0;
        else value = Number(raw);
      }
      values[column] = value;
    }
    for (let i = 0; i < values.length; i++) if (values[i] === undefined) values[i] = null;
    rows[rowIndex] = values;
  }
  for (let i = 0; i < rows.length; i++) if (rows[i] === undefined) rows[i] = [];
  return rows;
}

/**
 * Reads the sheets whose names pass [wanted] (all when omitted). Columns at
 * or beyond [maxColumns] are ignored, which keeps sheets whose formatting
 * reaches column XFD cheap.
 */
export function readXlsx(
  bytes: Uint8Array,
  wanted?: (name: string) => boolean,
  maxColumns = 40,
): Map<string, SheetRows> {
  const index = unzipSync(bytes, {
    filter: (file) => file.name === "xl/workbook.xml" || file.name === "xl/_rels/workbook.xml.rels",
  });
  const paths = sheetPaths(index);
  const chosen = new Map<string, string>();
  for (const [name, path] of paths) if (!wanted || wanted(name)) chosen.set(name, path);
  const needed = new Set<string>([...chosen.values(), "xl/sharedStrings.xml"]);
  const files = unzipSync(bytes, { filter: (file) => needed.has(file.name) });
  const strings = sharedStrings(files["xl/sharedStrings.xml"] ? strFromU8(files["xl/sharedStrings.xml"]) : undefined);
  const result = new Map<string, SheetRows>();
  for (const [name, path] of chosen) {
    const part = files[path];
    if (part) result.set(name, parseSheet(strFromU8(part), strings, maxColumns));
  }
  return result;
}

/** Converts an Excel date serial (1900 system) to yyyy-mm-dd. */
export function excelSerialToIso(serial: number): string | null {
  if (!Number.isFinite(serial) || serial < 1) return null;
  const date = new Date(Date.UTC(1899, 11, 30) + Math.round(serial * 86400000));
  return date.toISOString().slice(0, 10);
}
