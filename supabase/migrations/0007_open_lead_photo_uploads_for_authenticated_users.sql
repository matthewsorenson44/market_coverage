-- MVP repair: allow signed-in app users to manage lead photos.
--
-- Use this if photo uploads still fail with:
--   StorageException(message: new row violates row-level security policy,
--   statusCode: 403, error: Unauthorized)
--
-- The app already stores each file under:
--   lead-photos/<lead_id>/<timestamp>.<extension>
--
-- This policy is intentionally simpler than the lead-row ownership policy so
-- photo uploads work reliably while the account/lead RLS model is still
-- evolving. Keep the bucket public for image display, but require an
-- authenticated Supabase session to upload, update, or delete.

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'lead-photos',
  'lead-photos',
  true,
  10485760,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "lead photos readable"
  on storage.objects;
drop policy if exists "lead photos insert for owned leads"
  on storage.objects;
drop policy if exists "lead photos update for owned leads"
  on storage.objects;
drop policy if exists "lead photos delete for owned leads"
  on storage.objects;
drop policy if exists "lead photos readable by signed in users"
  on storage.objects;
drop policy if exists "lead photos insert by signed in users"
  on storage.objects;
drop policy if exists "lead photos update by signed in users"
  on storage.objects;
drop policy if exists "lead photos delete by signed in users"
  on storage.objects;

create policy "lead photos readable by signed in users"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'lead-photos');

create policy "lead photos insert by signed in users"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'lead-photos');

create policy "lead photos update by signed in users"
  on storage.objects
  for update
  to authenticated
  using (bucket_id = 'lead-photos')
  with check (bucket_id = 'lead-photos');

create policy "lead photos delete by signed in users"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'lead-photos');
