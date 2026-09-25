-- Storage compares the upload's content type in lower case, so an .xlsm file
-- sent as application/vnd.ms-excel.sheet.macroEnabled.12 was rejected with
-- 415 "application/vnd.ms-excel.sheet.macroenabled.12 is not supported"
-- (owner's Weekly Meeting upload, 2026-09-25). Allow both spellings.
update storage.buckets
set allowed_mime_types = array[
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-excel.sheet.macroEnabled.12',
  'application/vnd.ms-excel.sheet.macroenabled.12',
  'application/octet-stream'
]
where id = 'data-source-uploads';
