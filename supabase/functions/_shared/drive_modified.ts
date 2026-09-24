// Drive's "Date modified" for shared files, read from the Last-Modified header
// of a HEAD request (no API key needed). Screens show it as "Terakhir
// diperbarui" so the owner can match it with what Drive shows.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Newest Last-Modified of [fileIds] as ISO text, or null if none answered. */
export async function driveModifiedAt(fileIds: string[]): Promise<string | null> {
  const times = await Promise.all(fileIds.map(async (id) => {
    try {
      const response = await fetch(
        `https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=t`,
        { method: "HEAD", signal: AbortSignal.timeout(15000) },
      );
      const value = response.headers.get("last-modified");
      return value ? new Date(value).getTime() : NaN;
    } catch {
      return NaN;
    }
  }));
  const valid = times.filter((time) => Number.isFinite(time));
  return valid.length === 0 ? null : new Date(Math.max(...valid)).toISOString();
}

/**
 * Stores the files' modified time for [source] in data_source_status. Never
 * throws: a missing date must not fail the import itself.
 */
export async function recordDriveModified(
  admin: SupabaseClient,
  source: string,
  fileIds: string[],
): Promise<void> {
  try {
    const modifiedAt = await driveModifiedAt(fileIds);
    await admin.from("data_source_status").upsert(
      { source, checked_at: new Date().toISOString(), ...(modifiedAt ? { modified_at: modifiedAt } : {}) },
      { onConflict: "source" },
    );
  } catch (error) {
    console.error(`Could not record the modified time of ${source}`, error);
  }
}
