-- Repair lead photo Storage policies after the account model was added.
--
-- Symptom fixed:
--   StorageException(message: new row violates row-level security policy,
--   statusCode: 403, error: Unauthorized)
--
-- The app uploads photos to:
--   lead-photos/<lead_id>/<timestamp>.<extension>
--
-- Access is allowed when the signed-in user owns the lead, created the lead,
-- or belongs to the lead's account. The helper is SECURITY DEFINER so Storage
-- policy checks do not get blocked by lead/account RLS while evaluating access.

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

create or replace function public.can_manage_lead_photo_object(object_name text)
returns boolean
language sql
security definer
set search_path = public, storage
as $$
  select exists (
    select 1
    from public.leads as l
    where l.id::text = (storage.foldername(object_name))[1]
      and (
        l.user_id = auth.uid()
        or l.created_by = auth.uid()
        or exists (
          select 1
          from public.account_members as member
          where member.account_id = l.account_id
            and member.user_id = auth.uid()
        )
      )
  );
$$;

revoke all on function public.can_manage_lead_photo_object(text) from public;
grant execute on function public.can_manage_lead_photo_object(text)
  to authenticated;

drop policy if exists "lead photos readable"
  on storage.objects;
drop policy if exists "lead photos insert for owned leads"
  on storage.objects;
drop policy if exists "lead photos update for owned leads"
  on storage.objects;
drop policy if exists "lead photos delete for owned leads"
  on storage.objects;

create policy "lead photos readable"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.can_manage_lead_photo_object(name)
  );

create policy "lead photos insert for owned leads"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'lead-photos'
    and public.can_manage_lead_photo_object(name)
  );

create policy "lead photos update for owned leads"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.can_manage_lead_photo_object(name)
  )
  with check (
    bucket_id = 'lead-photos'
    and public.can_manage_lead_photo_object(name)
  );

create policy "lead photos delete for owned leads"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'lead-photos'
    and public.can_manage_lead_photo_object(name)
  );
