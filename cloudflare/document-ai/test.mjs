import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { snippets, validateAnswer } from './src/index.js';
const docs = [{ id: 1, text: 'Warna kotak pada dokumen uji adalah hijau.' }];
test('kutipan harus ada pada sumber yang diberikan', () => {
  assert.equal(validateAnswer({ answer:'hijau', citations:[{id:1,excerpt:docs[0].text}] }, docs).answer, 'hijau');
  for (const citation of [{id:2,excerpt:docs[0].text},{id:1,excerpt:'Warna kotak pada dokumen uji adalah merah.'}]) {
    assert.deepEqual(validateAnswer({answer:'merah',citations:[citation]},docs).citations, []);
  }
});
test('jawaban bercampur kutipan palsu ditolak seluruhnya', () => {
  assert.deepEqual(validateAnswer({answer:'hijau dan merah',citations:[{id:1,excerpt:docs[0].text},{id:2,excerpt:docs[0].text}]},docs).citations, []);
});
test('kutipan prosedur asli dipakai saat model gagal membuat sitasi valid', () => {
  const procedure = 'Prosedur Mode Auto: Posisikan switch pada panel power distribusi OLC ke posisi Remote. Conveyor dikendalikan oleh control room.';
  const result = validateAnswer(
    { answer: 'Tidak ada jawaban.', citations: [] },
    [{ id: 1, name: 'Pengoperasian Conveyor VSD.docx', text: procedure }],
    'bagaimana cara prosedur mode auto VSD',
  );
  assert.match(result.answer, /Posisikan switch/);
  assert.deepEqual(result.citations, [{ id: 1, excerpt: procedure }]);
});
test('potongan relevan dari akhir dokumen tetap ditemukan', () => {
  const text = 'pendahuluan '.repeat(2000) + ' Sandblasting membutuhkan pemeriksaan alat.';
  assert.match(snippets(text,'alat sandblasting'), /Sandblasting membutuhkan/);
});
test('endpoint menolak akses tanpa kunci server', async () => {
  const result = await worker.fetch(new Request('https://test/',{method:'POST'}),{DOCUMENT_AI_TOKEN:'test'},{});
  assert.equal(result.status,401);
});
