-- =========================================================
-- Fotos das clientes (Supabase Storage, bucket privado)
-- Rode uma vez no SQL Editor do Supabase.
-- Cada conta só enxerga as fotos da própria pasta: <id da usuária>/...
-- =========================================================

alter table public.clients add column if not exists photo_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('client-photos', 'client-photos', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists "client_photos_select" on storage.objects;
drop policy if exists "client_photos_insert" on storage.objects;
drop policy if exists "client_photos_update" on storage.objects;
drop policy if exists "client_photos_delete" on storage.objects;

create policy "client_photos_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'client-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "client_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'client-photos'
              and (storage.foldername(name))[1] = auth.uid()::text);

create policy "client_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'client-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);

create policy "client_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'client-photos'
         and (storage.foldername(name))[1] = auth.uid()::text);
