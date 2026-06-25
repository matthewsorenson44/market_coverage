-- Lead photo storage setup.
--
-- Required by LeadDetailsScreen photo uploads:
--   bucket: lead-photos
--   path:   <lead_id>/<timestamp>.<extension>
--
-- Run this in Supabase SQL Editor if photo upload says the bucket is missing
-- or the storage policy blocks the upload.

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

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'lead photos readable'
  ) then
    create policy "lead photos readable"
      on storage.objects
      for select
      to authenticated
      using (bucket_id = 'lead-photos');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'lead photos insert for owned leads'
  ) then
    create policy "lead photos insert for owned leads"
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'lead-photos'
        and exists (
          select 1
          from public.leads
          where id::text = (storage.foldername(name))[1]
            and user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'lead photos update for owned leads'
  ) then
    create policy "lead photos update for owned leads"
      on storage.objects
      for update
      to authenticated
      using (
        bucket_id = 'lead-photos'
        and exists (
          select 1
          from public.leads
          where id::text = (storage.foldername(name))[1]
            and user_id = auth.uid()
        )
      )
      with check (
        bucket_id = 'lead-photos'
        and exists (
          select 1
          from public.leads
          where id::text = (storage.foldername(name))[1]
            and user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'lead photos delete for owned leads'
  ) then
    create policy "lead photos delete for owned leads"
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'lead-photos'
        and exists (
          select 1
          from public.leads
          where id::text = (storage.foldername(name))[1]
            and user_id = auth.uid()
        )
      );
  end if;
end $$;
