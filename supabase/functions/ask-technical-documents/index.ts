// Answers are intentionally grounded only in public files beneath the approved
// Google Drive folder. The Flutter client never receives the Gemini API key.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const rootFolderId = "1Mrt4ND-wPgkfmCngbmTfHBwyAo1oclxp";
const folderUrl = (id: string) => `https://drive.google.com/drive/folders/${id}?usp=sharing`;
const viewUrl = (id: string) => `https://drive.google.com/file/d/${id}/view?usp=drive_link`;
const downloadUrl = (id: string) => `https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t`;

type DriveEntry = { id: string; name: string; path: string; isFolder: boolean };
type LoadedDocument = DriveEntry & { mimeType: string; data: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function decodeHtml(value: string) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&nbsp;", " ");
}

function cleanName(ariaLabel: string) {
  return decodeHtml(ariaLabel)
    .replace(/\s+(?:Shared\s+)?folder$/i, "")
    .replace(/\s+(?:PDF|Microsoft Word|Microsoft Excel|Microsoft PowerPoint|Unknown)$/i, "")
    .replace(/\s+Shared$/i, "")
    .trim();
}

function parseFolder(html: string, parentPath: string): DriveEntry[] {
  const entries = new Map<string, DriveEntry>();
  // Drive's public folder page pairs the file ID and display label on the
  // same element. Parsing that pair avoids accidentally treating controls
  // such as "More actions" as documents.
  const pattern = /data-id="([A-Za-z0-9_-]{12,})"[^>]*data-tooltip="([^"]+)"/g;
  for (const match of html.matchAll(pattern)) {
    const id = match[1];
    const ariaLabel = decodeHtml(match[2]);
    const name = cleanName(ariaLabel);
    if (!name || id === rootFolderId || entries.has(id)) continue;
    const isFolder = /(?:Shared\s+)?folder$/i.test(ariaLabel);
    entries.set(id, { id, name, path: parentPath, isFolder });
  }
  return [...entries.values()];
}

async function listDocuments(): Promise<DriveEntry[]> {
  const documents: DriveEntry[] = [];
  const visited = new Set<string>();
  let queue = [{ id: rootFolderId, path: "Pusat Dokumen", depth: 0 }];

  // Several folders are fetched together. A recursive serial crawl of a public
  // Drive folder is slow enough to make an otherwise valid AI request time out.
  while (queue.length > 0 && documents.length < 240) {
    const batch = queue.splice(0, 5).filter((folder) => {
      if (folder.depth > 4 || visited.has(folder.id)) return false;
      visited.add(folder.id);
      return true;
    });
    const results = await Promise.all(batch.map(async (folder) => {
      const response = await fetch(folderUrl(folder.id), { signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error(`Folder Google Drive tidak dapat dibaca (HTTP ${response.status}).`);
      return { folder, entries: parseFolder(await response.text(), folder.path) };
    }));
    for (const { folder, entries } of results) {
      for (const entry of entries) {
        if (entry.isFolder) {
          queue.push({ id: entry.id, path: `${folder.path}/${entry.name}`, depth: folder.depth + 1 });
        } else if (documents.length < 240) {
          documents.push(entry);
        }
      }
    }
  }
  return documents;
}

function queryTerms(question: string) {
  return [...new Set(question.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((term) => term.length >= 3))];
}

function selectDocuments(question: string, documents: DriveEntry[]) {
  const terms = queryTerms(question);
  return documents
    .map((document) => {
      const haystack = `${document.name} ${document.path}`.toLowerCase();
      const score = terms.reduce((total, term) => total + (haystack.includes(term) ? 1 : 0), 0);
      return { document, score };
    })
    .filter((item) => item.score > 0)
    .sort((left, right) => right.score - left.score || left.document.name.localeCompare(right.document.name))
    .slice(0, 8)
    .map((item) => item.document);
}

function base64(bytes: Uint8Array) {
  let output = "";
  const chunkSize = 0x8000;
  for (let index = 0; index < bytes.length; index += chunkSize) {
    output += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(output);
}

function supportedMimeType(name: string, responseMimeType: string | null) {
  const extension = name.toLowerCase().split(".").pop();
  if (extension === "pdf") return "application/pdf";
  if (extension === "txt" || extension === "md") return "text/plain";
  if (extension === "csv") return "text/csv";
  return responseMimeType?.split(";")[0] ?? "application/octet-stream";
}

async function loadDocument(entry: DriveEntry): Promise<LoadedDocument | null> {
  const response = await fetch(downloadUrl(entry.id), { signal: AbortSignal.timeout(20000) });
  if (!response.ok) return null;
  const bytes = new Uint8Array(await response.arrayBuffer());
  const mimeType = supportedMimeType(entry.name, response.headers.get("content-type"));
  const allowed = mimeType === "application/pdf" || mimeType.startsWith("text/");
  if (!allowed || bytes.length === 0 || bytes.length > 8 * 1024 * 1024) return null;
  return { ...entry, mimeType, data: base64(bytes) };
}

function textFromModel(data: Record<string, unknown>) {
  const candidates = data.candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) throw new Error("Model AI tidak memberikan jawaban.");
  const content = candidates[0] as Record<string, unknown>;
  const parts = (content.content as Record<string, unknown> | undefined)?.parts;
  if (!Array.isArray(parts)) throw new Error("Model AI tidak memberikan jawaban.");
  return parts.map((part) => (part as Record<string, unknown>).text).filter((text) => typeof text === "string").join("\n");
}

function parseModelJson(value: string): Record<string, unknown> {
  const first = value.indexOf("{");
  const last = value.lastIndexOf("}");
  if (first < 0 || last <= first) throw new Error("Jawaban AI tidak dapat dibaca.");
  const parsed = JSON.parse(value.slice(first, last + 1));
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Jawaban AI tidak dapat dibaca.");
  }
  return parsed as Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Metode tidak diizinkan." }, 405);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ ok: false, error: "Silakan masuk ke SICATAT terlebih dahulu." }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return json({ ok: false, error: "Konfigurasi server SICATAT belum lengkap." }, 503);
  }
  const caller = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return json({ ok: false, error: "Sesi masuk tidak valid." }, 401);
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return json({ ok: false, error: "Pencarian AI belum diaktifkan. Administrator perlu memasang GEMINI_API_KEY di server." }, 503);
  }
  try {
    const body = await req.json() as { question?: unknown };
    const question = typeof body.question === "string" ? body.question.trim() : "";
    if (question.length < 4 || question.length > 600) {
      return json({ ok: false, error: "Pertanyaan harus terdiri dari 4 sampai 600 karakter." }, 400);
    }
    const documents = await listDocuments();
    const selected = selectDocuments(question, documents);
    if (selected.length === 0) {
      return json({ ok: true, answer: "Saya tidak menemukan nama file yang relevan di folder dokumen. Coba gunakan istilah SOP, nomor dokumen, atau nama pekerjaan yang lebih spesifik.", sources_scanned: 0, citations: [] });
    }
    const loaded: LoadedDocument[] = [];
    let totalBytes = 0;
    for (const entry of selected) {
      const file = await loadDocument(entry);
      if (file && totalBytes + file.data.length <= 18 * 1024 * 1024) {
        loaded.push(file);
        totalBytes += file.data.length;
      }
    }
    if (loaded.length === 0) {
      return json({ ok: true, answer: "File yang relevan ditemukan, tetapi tidak dapat dibaca AI. Buka file sumber untuk melihat atau mengunduhnya.", sources_scanned: 0, citations: selected.map((item) => ({ name: item.name, url: viewUrl(item.id) })) });
    }
    const documentList = loaded.map((item, index) => `[${index + 1}] ${item.name} — ${item.path}`).join("\n");
    const instruction = [
      "Anda adalah asisten Pusat Dokumen SICATAT.",
      "Jawab dalam Bahasa Indonesia hanya berdasarkan isi file yang dilampirkan pada permintaan ini.",
      "Jangan gunakan pengetahuan umum, internet, dugaan, atau sumber lain.",
      "Jika jawaban tidak tercantum jelas, katakan bahwa dokumen yang diperiksa belum cukup.",
      "Kembalikan JSON valid tanpa markdown dengan bentuk: {\\\"answer\\\": string, \\\"citations\\\": [{\\\"id\\\": number, \\\"excerpt\\\": string}] }.",
      "citation.id harus nomor dokumen pada daftar, dan excerpt harus kutipan pendek yang mendukung jawaban.",
      `Pertanyaan pengguna: ${question}`,
      "Dokumen yang diizinkan:",
      documentList,
    ].join("\n\n");
    const parts: Array<Record<string, unknown>> = [{ text: instruction }];
    for (let index = 0; index < loaded.length; index += 1) {
      parts.push({ text: `Dokumen [${index + 1}]: ${loaded[index].name}` });
      parts.push({ inlineData: { mimeType: loaded[index].mimeType, data: loaded[index].data } });
    }
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({ contents: [{ role: "user", parts }], generationConfig: { temperature: 0.1, maxOutputTokens: 900, responseMimeType: "application/json" } }),
      signal: AbortSignal.timeout(55000),
    });
    if (!response.ok) throw new Error(`Model AI tidak dapat dihubungi (HTTP ${response.status}).`);
    const modelJson = parseModelJson(textFromModel(await response.json()));
    const rawCitations = Array.isArray(modelJson.citations) ? modelJson.citations : [];
    const citations = rawCitations.flatMap((citation) => {
      const value = citation as Record<string, unknown>;
      const index = Number(value.id) - 1;
      const source = loaded[index];
      if (!source) return [];
      return [{ name: source.name, url: viewUrl(source.id), excerpt: typeof value.excerpt === "string" ? value.excerpt.slice(0, 280) : undefined }];
    });
    return json({ ok: true, answer: typeof modelJson.answer === "string" ? modelJson.answer : "Jawaban AI belum tersedia.", sources_scanned: loaded.length, citations });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Pencarian dokumen gagal.";
    console.error("ask-technical-documents failed:", message);
    return json({ ok: false, error: message }, 500);
  }
});
