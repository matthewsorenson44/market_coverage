-- User-scoped lead photo Storage policy.
--
-- The app uploads photos to:
--   lead-photos/<auth_user_id>/<lead_id>/<timestamp>.<extension>
--
-- This avoids the lead/account RLS mismatch that caused Storage 403 errors,
-- while still requiring a signed-in Supabase user. The first folder segment
-- must match auth.uid().

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
drop policy if exists "lead photos mvp read"
  on storage.objects;
drop policy if exists "lead photos mvp insert"
  on storage.objects;
drop policy if exists "lead photos mvp update"
  on storage.objects;
drop policy if exists "lead photos mvp delete"
  on storage.objects;
drop policy if exists "lead photos user folder read"
  on storage.objects;
drop policy if exists "lead photos user folder insert"
  on storage.objects;
drop policy if exists "lead photos user folder update"
  on storage.objects;
drop policy if exists "lead photos user folder delete"
  on storage.objects;

create policy "lead photos user folder read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "lead photos user folder insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'lead-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "lead photos user folder update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'lead-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "lead photos user folder delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
