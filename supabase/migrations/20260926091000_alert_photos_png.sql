-- A small PNG is kept as it is by the photo compressor (re-encoding it would
-- make it larger), so the follow-up photo bucket accepts PNG as well.
update storage.buckets
set allowed_mime_types = array['image/jpeg', 'image/png']
where id = 'temperature-alert-photos';
