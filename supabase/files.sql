-- Practice Desk CRM: private file storage (signed contracts, AML evidence, IDs).
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run (safe to run again).
-- Only signed-in members who passed two-factor sign-in (public.can_use()) can upload, open or delete files.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('files', 'files', false, 20971520,
        array['application/pdf','image/jpeg','image/png','image/heic','image/webp',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "members read files"   on storage.objects;
drop policy if exists "members upload files" on storage.objects;
drop policy if exists "members update files" on storage.objects;
drop policy if exists "members delete files" on storage.objects;
create policy "members read files"   on storage.objects for select to authenticated using (bucket_id = 'files' and public.can_use());
create policy "members upload files" on storage.objects for insert to authenticated with check (bucket_id = 'files' and public.can_use());
create policy "members update files" on storage.objects for update to authenticated using (bucket_id = 'files' and public.can_use()) with check (bucket_id = 'files' and public.can_use());
create policy "members delete files" on storage.objects for delete to authenticated using (bucket_id = 'files' and public.can_use());
