# SICATAT document AI

Server-only Cloudflare Workers AI adapter. Flutter web and Android continue calling the authenticated Supabase `ask-technical-documents` function. That function crawls only the approved public Drive folder and forwards selected document bytes to this Worker. The client cannot choose an arbitrary document URL or the model.

## Deployment

- Deploy `wrangler deploy --config cloudflare/document-ai/wrangler.jsonc` from the repository root.
- Worker secret: `DOCUMENT_AI_TOKEN`.
- Matching Supabase secrets: `CLOUDFLARE_DOCUMENTS_TOKEN` and `CLOUDFLARE_DOCUMENTS_URL`.
- Never commit or print these values. No Cloudflare account token is sent to Supabase or Flutter.
- URL: https://sicatat-document-ai.sicatat.workers.dev
- Model: `@cf/qwen/qwen3-30b-a3b-fp8`. No billing upgrade was performed. Free quota remains limited; reaching it must not trigger paid fallback.

## Verification and limits

Run `node --test cloudflare/document-ai/test.mjs` and `node supabase/functions/ask-technical-documents/diagnostics.test.mjs`.

Document extraction uses Cloudflare `AI.toMarkdown`, with content-hash cache for one day. PDF metadata without page text is excluded. The actual ASM-COP-160 PDF converted to empty pages; its Word counterpart contains readable text and was successfully used for the three-person answer. OCR/drawing understanding is not verified. Unsupported/empty documents are not evidence.

Retrieval is currently by document name/path, then relevant text chunks within selected files; it is NOT an exhaustive full-content index. Public embedded Drive listing fixes the standard page's first-150-item truncation. Crawl is bounded to 3000 entries/depth 4; at most 8 candidate files are processed, 8 MB each and 18 MB total base64. Cache is regional, not a global concurrency guarantee. Ten simultaneous users have not been load-tested.

Responses without matching source excerpts are rejected. This checks excerpt membership, not complete semantic entailment of every generated claim. Users must verify the linked SOP before carrying out safety-critical work. The generated response is not a replacement for the approved procedure.
