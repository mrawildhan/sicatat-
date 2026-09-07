import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace(/import \{ createClient \}[^;]+;/, '')
  .split('Deno.serve(')[0];
const code = stripTypeScriptTypes(source + '\nexport {geminiFailure, selectModelCandidates, parseFolder, selectDocuments, uniqueCitations};');
const { geminiFailure, selectModelCandidates, parseFolder, selectDocuments, uniqueCitations } = await import(
  'data:text/javascript;base64,' + Buffer.from(code).toString('base64')
);
for (const [status, message, expected] of [
  [403, 'Your API key was reported as leaked', 'KEY_BLOCKED'],
  [403, 'Your project has been denied access', 'PROJECT_ACCESS_DENIED'],
  [403, 'API is disabled', 'API_DISABLED'],
  [403, 'HTTP referrer is blocked', 'KEY_RESTRICTED'],
  [400, 'API key not valid', 'KEY_INVALID'],
  [429, 'Quota exceeded', 'QUOTA_LIMIT'],
]) {
  const result = await geminiFailure(new Response(JSON.stringify({ error: { message } }), {
    status, headers: { 'content-type': 'application/json' },
  }));
  assert.ok(result.message.includes(expected));
}
assert.match((await geminiFailure(new Response('Forbidden', { status: 403 }))).message, /GATEWAY_ACCESS_DENIED/);
assert.deepEqual(selectModelCandidates('gemini-2.5-flash', [
  'gemini-2.5-flash', 'gemini-3.1-flash-lite', 'gemini-unapproved-flash',
]), ['gemini-3.1-flash-lite', 'gemini-2.5-flash']);
console.log('PASS: 7 safe error classifications and bounded model selection');
const entries = parseFolder('<div class="flip-entry" id="entry-document123456"><a href="https://drive.google.com/file/d/document123456/view"><div class="flip-entry-title">ASM-COP-160 Sandblasting.pdf</div></a></div>', 'Pusat Dokumen');
assert.equal(entries[0].name, 'ASM-COP-160 Sandblasting.pdf');
assert.equal(entries[0].isFolder, false);
assert.deepEqual(selectDocuments('berapa minimal orang untuk pekerjaan sandblasting', [...entries, {id:'other',name:'Untuk pekerjaan lain.pdf',path:'Pusat Dokumen'}]), entries);
const vsd = selectDocuments('bagaimana cara prosedur Mode Auto vsd', [
  { id: 'power-docx', name: 'ASM-COP-157 Penggantian Power Block VSD Siemens.docx', path: 'Pusat Dokumen/SOP' },
  { id: 'power-pdf', name: 'ASM-COP-157 Penggantian Power Block VSD Siemens.pdf', path: 'Pusat Dokumen/SOP' },
  { id: 'operation-docx', name: 'ASM-COP-158 Operasional VSD.docx', path: 'Pusat Dokumen/SOP' },
  { id: 'operation-pdf', name: 'ASM-COP-158 Operasional VSD.pdf', path: 'Pusat Dokumen/SOP' },
]);
assert.deepEqual(vsd.map((entry) => entry.id), ['operation-docx', 'power-docx']);
const bodyHarness = selectDocuments('kapan body harness wajib digunakan?', [
  { id: 'roller', name: 'ASM-COP-150 Pergantian Roller & Frame Roller.docx', path: 'Pusat Dokumen/SOP' },
  { id: 'other', name: 'ASM-COP-151 Penggantian Belt.docx', path: 'Pusat Dokumen/SOP' },
]);
assert.deepEqual(bodyHarness.map((entry) => entry.id), ['roller']);
assert.deepEqual(
  uniqueCitations([
    { name: 'ASM-COP-107 Penyandaran Tongkang.docx', url: 'https://drive.google.com/file/d/107/view', excerpt: 'Kutipan pertama' },
    { name: 'ASM-COP-107 Penyandaran Tongkang.docx', url: 'https://drive.google.com/file/d/107/view', excerpt: 'Kutipan kedua' },
    { name: 'ASM-COP-150 Pergantian Roller.docx', url: 'https://drive.google.com/file/d/150/view', excerpt: 'Kutipan ketiga' },
  ]).map((citation) => citation.name),
  ['ASM-COP-107 Penyandaran Tongkang.docx', 'ASM-COP-150 Pergantian Roller.docx'],
);
console.log('PASS: embedded Drive listing and relevant document selection');
