// Where a spreadsheet part comes from: a file an admin uploaded through
// "Unggah data" (Storage bucket data-source-uploads), or its public Drive link.
//
// An upload lands in incoming/<part>. The sync function imports it together
// with the other parts of its source and calls promoteUpload() only after the
// import succeeded, so a broken file never replaces a working one. While
// current/<part> exists the Drive link of that part is ignored.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { driveModifiedAt } from "./drive_modified.ts";

const bucket = "data-source-uploads";

export type PendingUpload = { part: string; fileName: string; size: number };

export type SourceParts = {
  /** Parts that currently read from an uploaded file, with the upload time. */
  uploaded: Map<string, string>;
  /** The part being uploaded in this request, if any. */
  pending: PendingUpload | null;
};

/**
 * Reads {"upload": {"part", "file_name", "size"}} from the request body. Only
 * active admins may upload, and only parts this function owns.
 */
export async function readPendingUpload(
  body: Record<string, unknown>,
  ownParts: string[],
  isAdmin: boolean,
): Promise<PendingUpload | null> {
  const upload = body.upload as Record<string, unknown> | undefined;
  if (!upload) return null;
  const part = String(upload.part ?? "");
  if (!ownParts.includes(part)) throw new Error("Jenis file tidak dikenal.");
  if (!isAdmin) throw new Error("Hanya admin yang dapat mengunggah data.");
  return {
    part,
    fileName: String(upload.file_name ?? part).slice(0, 200),
    size: Number(upload.size ?? 0) || 0,
  };
}

/** Request body as an object; empty when the app sent none. */
export async function requestBody(req: Request): Promise<Record<string, unknown>> {
  try {
    const value = await req.json();
    return value && typeof value === "object" ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

export async function loadSourceParts(
  admin: SupabaseClient,
  parts: string[],
  pending: PendingUpload | null,
): Promise<SourceParts> {
  const { data, error } = await admin
    .from("data_source_upload")
    .select("part,uploaded_at")
    .in("part", parts);
  if (error) throw error;
  const uploaded = new Map<string, string>();
  for (const row of data ?? []) uploaded.set(row.part as string, row.uploaded_at as string);
  return { uploaded, pending };
}

/** Bytes of [part]: the pending upload, the stored upload, or Drive. */
export async function readPart(
  admin: SupabaseClient,
  sources: SourceParts,
  part: string,
  label: string,
  fromDrive: () => Promise<Uint8Array>,
): Promise<Uint8Array> {
  const folder = sources.pending?.part === part
    ? "incoming"
    : sources.uploaded.has(part)
    ? "current"
    : null;
  if (!folder) return await fromDrive();
  const { data, error } = await admin.storage.from(bucket).download(`${folder}/${part}`);
  if (error || !data) throw new Error(`File unggahan ${label} tidak dapat dibaca.`);
  const bytes = new Uint8Array(await data.arrayBuffer());
  // xlsx/xlsm files are zip archives.
  if (bytes[0] !== 0x50 || bytes[1] !== 0x4b) {
    throw new Error(`${label} bukan file Excel (.xlsx/.xlsm).`);
  }
  return bytes;
}

/** True when [part] must be read from an upload rather than Drive. */
export function usesUpload(sources: SourceParts, part: string): boolean {
  return sources.pending?.part === part || sources.uploaded.has(part);
}

/** Makes the imported pending upload the current file of its part. */
export async function promoteUpload(
  admin: SupabaseClient,
  source: string,
  pending: PendingUpload | null,
  callerId: string,
): Promise<void> {
  if (!pending) return;
  const storage = admin.storage.from(bucket);
  await storage.remove([`current/${pending.part}`]);
  const { error: moveError } = await storage.move(`incoming/${pending.part}`, `current/${pending.part}`);
  if (moveError) throw moveError;
  const { error } = await admin.from("data_source_upload").upsert({
    part: pending.part,
    source,
    file_name: pending.fileName,
    size_bytes: pending.size,
    uploaded_at: new Date().toISOString(),
    uploaded_by: callerId,
  }, { onConflict: "part" });
  if (error) throw error;
}

/** Drops a pending upload whose import failed. Never throws. */
export async function discardUpload(admin: SupabaseClient, pending: PendingUpload | null): Promise<void> {
  if (!pending) return;
  try {
    await admin.storage.from(bucket).remove([`incoming/${pending.part}`]);
  } catch (error) {
    console.error(`Could not remove incoming/${pending.part}`, error);
  }
}

/**
 * Newest "last changed" time over [parts]: the upload time for uploaded
 * parts, Drive's Date modified for the others. Stored in data_source_status
 * for [source]; never throws.
 */
export async function recordSourceModified(
  admin: SupabaseClient,
  source: string,
  parts: { part: string; driveId: string }[],
): Promise<void> {
  try {
    const { data } = await admin
      .from("data_source_upload")
      .select("part,uploaded_at")
      .in("part", parts.map((p) => p.part));
    const uploaded = new Map<string, string>();
    for (const row of data ?? []) uploaded.set(row.part as string, row.uploaded_at as string);
    const times: number[] = [];
    for (const p of parts) {
      const at = uploaded.get(p.part);
      if (at) times.push(new Date(at).getTime());
    }
    const driveIds = parts.filter((p) => !uploaded.has(p.part)).map((p) => p.driveId);
    const drive = driveIds.length === 0 ? null : await driveModifiedAt(driveIds);
    if (drive) times.push(new Date(drive).getTime());
    const modifiedAt = times.length === 0 ? null : new Date(Math.max(...times)).toISOString();
    await admin.from("data_source_status").upsert(
      { source, checked_at: new Date().toISOString(), ...(modifiedAt ? { modified_at: modifiedAt } : {}) },
      { onConflict: "source" },
    );
  } catch (error) {
    console.error(`Could not record the modified time of ${source}`, error);
  }
}

/**
 * Thrown before anything is written when an uploaded file holds far less
 * than the current data (e.g. only the 200 new PR rows instead of the whole
 * file). The pending upload is kept so the admin can confirm and retry.
 */
export class ShrinkNeedsConfirmation extends Error {
  constructor(readonly newCount: number, readonly currentCount: number, readonly unit: string) {
    super(`File ini berisi ${newCount} ${unit}, data sekarang ${currentCount} ${unit}.`);
  }
}

/** Upload drops below half of the current data without confirmation. */
export function checkShrink(
  pending: PendingUpload | null,
  body: Record<string, unknown>,
  newCount: number,
  currentCount: number,
  unit: string,
): void {
  if (!pending || body.confirm_shrink === true) return;
  if (currentCount > 0 && newCount < currentCount * 0.5) {
    throw new ShrinkNeedsConfirmation(Math.round(newCount), Math.round(currentCount), unit);
  }
}

/** Number of rows in [table], optionally where [column] = [value]. */
export async function rowCount(
  admin: SupabaseClient,
  table: string,
  column?: string,
  value?: string,
): Promise<number> {
  let query = admin.from(table).select("*", { count: "exact", head: true });
  if (column && value !== undefined) query = query.eq(column, value);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

/** JSON answer asking the admin to confirm a shrinking upload. */
export function shrinkAnswer(error: ShrinkNeedsConfirmation) {
  return {
    ok: false,
    needs_confirmation: true,
    new_count: error.newCount,
    current_count: error.currentCount,
    unit: error.unit,
    error: error.message,
  };
}

/** Whether the caller is an active admin (uploads are admin-only). */
export async function isActiveAdmin(admin: SupabaseClient, callerId: string): Promise<boolean> {
  const { data } = await admin.from("app_user").select("role,is_active").eq("id", callerId).maybeSingle();
  return data?.role === "admin" && data?.is_active === true;
}

/** Message of an Error or a Supabase error object. */
export function errorText(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "object" && error !== null && "message" in error) {
    return String((error as { message: unknown }).message);
  }
  return String(error);
}
