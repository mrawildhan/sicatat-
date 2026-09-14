#!/usr/bin/env node
// Renews the Gmail credentials used by SICATAT reminder emails.
//
// Run it yourself from the repository root:
//   node scripts/renew-gmail-refresh-token.mjs
//
// What it does:
// 1. Asks for the Google OAuth client ID and client secret (Google Cloud
//    Console -> APIs & Services -> Credentials). Input stays on this computer.
// 2. Opens Google's consent page. Sign in as arutminreminder@gmail.com and
//    allow "Send email on your behalf".
// 3. Exchanges the returned code for a refresh token and stores the GMAIL_*
//    secrets in Supabase through a temporary env file that is deleted right
//    away. No credential is printed or passed on the command line.
//
// Requirement: the OAuth client must allow the redirect URI printed below.
// A "Desktop app" client accepts loopback redirects without extra setup; for a
// "Web application" client add the URI under "Authorized redirect URIs".

import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { stdin, stdout } from "node:process";
import { createInterface } from "node:readline/promises";

const PROJECT_REF = "ofczleeyqrxyuuupzirq";
const SENDER = "arutminreminder@gmail.com";
const PORT = 53682;
const REDIRECT_URI = `http://127.0.0.1:${PORT}/callback`;
const SCOPE = "https://www.googleapis.com/auth/gmail.send";

function openBrowser(url) {
  if (process.platform === "win32") {
    spawn("rundll32", ["url.dll,FileProtocolHandler", url], {
      stdio: "ignore",
      detached: true,
    }).unref();
    return;
  }
  const opener = process.platform === "darwin" ? "open" : "xdg-open";
  spawn(opener, [url], { stdio: "ignore", detached: true }).unref();
}

// Start listening before the browser opens so a fast consent is not missed.
function listenForCode(state) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      server.close();
      reject(new Error("Waktu habis (5 menit) menunggu izin Google."));
    }, 5 * 60 * 1000);
    const server = http.createServer((req, res) => {
      const url = new URL(req.url ?? "/", REDIRECT_URI);
      if (url.pathname !== "/callback") {
        res.writeHead(404).end();
        return;
      }
      const error = url.searchParams.get("error");
      const code = url.searchParams.get("code");
      const ok = !error && code && url.searchParams.get("state") === state;
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      res.end(
        ok
          ? "<h2>Berhasil. Kembali ke terminal; jendela ini boleh ditutup.</h2>"
          : "<h2>Izin dibatalkan atau tidak valid. Jalankan skrip lagi.</h2>",
      );
      clearTimeout(timer);
      server.close();
      if (ok) resolve(code);
      else reject(new Error(error ?? "Respons OAuth tidak valid."));
    });
    server.on("error", reject);
    server.listen(PORT, "127.0.0.1");
  });
}

async function setSupabaseSecrets(values) {
  const dir = await mkdtemp(path.join(tmpdir(), "sicatat-gmail-"));
  const envFile = path.join(dir, "gmail.env");
  try {
    const content = Object.entries(values)
      .map(([name, value]) => `${name}=${JSON.stringify(value)}`)
      .join("\n");
    await writeFile(envFile, content + "\n", { mode: 0o600 });
    await new Promise((resolve, reject) => {
      const child = spawn(
        "npx",
        ["supabase", "secrets", "set", "--project-ref", PROJECT_REF, "--env-file", envFile],
        { stdio: ["ignore", "ignore", "pipe"], shell: process.platform === "win32" },
      );
      let stderr = "";
      child.stderr.on("data", (chunk) => (stderr += chunk));
      child.on("error", reject);
      child.on("close", (exitCode) =>
        exitCode === 0
          ? resolve()
          : reject(new Error("Gagal menyimpan secret ke Supabase: " + stderr.trim())),
      );
    });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

const rl = createInterface({ input: stdin, output: stdout });
console.log("Pembaruan token Gmail untuk email pengingat SICATAT\n");
console.log("Redirect URI yang harus diizinkan di OAuth client Google:");
console.log("  " + REDIRECT_URI + "\n");
const clientId = (await rl.question("Google OAuth Client ID: ")).trim();
const clientSecret = (await rl.question("Google OAuth Client secret: ")).trim();
rl.close();
if (!clientId || !clientSecret) {
  console.error("Client ID dan Client secret wajib diisi.");
  process.exit(1);
}
// A wrong paste (secret in the ID prompt, cut-off text, quotes) otherwise only
// surfaces as Google's "OAuth client was not found / invalid_client" page.
if (!/^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$/.test(clientId)) {
  console.error(
    "Client ID tidak valid. Formatnya angka-huruf yang diakhiri .apps.googleusercontent.com.\n" +
      "Salin ulang dari Google Auth Platform -> Clients (bukan Client secret), lalu jalankan lagi.",
  );
  process.exit(1);
}
if (clientSecret.endsWith(".apps.googleusercontent.com")) {
  console.error("Yang ditempel sebagai Client secret adalah Client ID. Jalankan lagi dan tempel secret-nya.");
  process.exit(1);
}

const state = randomBytes(16).toString("hex");
const codePromise = listenForCode(state);
const consentUrl =
  "https://accounts.google.com/o/oauth2/v2/auth?" +
  new URLSearchParams({
    client_id: clientId,
    redirect_uri: REDIRECT_URI,
    response_type: "code",
    scope: SCOPE,
    access_type: "offline",
    // Always show the account chooser so a browser already signed in to a
    // different Google account can switch to the sender mailbox.
    prompt: "select_account consent",
    login_hint: SENDER,
    state,
  });
console.log(
  "\nMembuka halaman izin Google. Masuk sebagai " + SENDER + " lalu klik Izinkan.",
);
console.log("Kalau browser tidak terbuka, salin alamat ini ke browser:\n" + consentUrl + "\n");
openBrowser(consentUrl);

let code;
try {
  code = await codePromise;
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}

const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    code,
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: REDIRECT_URI,
    grant_type: "authorization_code",
  }),
});
const tokenData = await tokenResponse.json().catch(() => ({}));
if (!tokenResponse.ok || typeof tokenData.refresh_token !== "string") {
  console.error(
    "Google tidak mengembalikan refresh token (" +
      (tokenData.error ?? tokenResponse.status) +
      "). Pastikan redirect URI sudah diizinkan, lalu jalankan lagi.",
  );
  process.exit(1);
}

console.log("Token diterima. Menyimpan ke Supabase...");
try {
  await setSupabaseSecrets({
    GMAIL_CLIENT_ID: clientId,
    GMAIL_CLIENT_SECRET: clientSecret,
    GMAIL_REFRESH_TOKEN: tokenData.refresh_token,
    GMAIL_SENDER_EMAIL: SENDER,
  });
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
}
console.log('Selesai. Secret GMAIL_* sudah diperbarui. Beri tahu Claude "sudah" untuk tes kirim.');
