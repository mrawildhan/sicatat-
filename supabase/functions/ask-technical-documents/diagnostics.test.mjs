import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
  .replace(/import \{ createClient \}[^;]+;/, '')
  .split('Deno.serve(')[0];
const code = stripTypeScriptTypes(source + '\nexport {geminiFailure, selectModelCandidates};');
const { geminiFailure, selectModelCandidates } = await import(
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
