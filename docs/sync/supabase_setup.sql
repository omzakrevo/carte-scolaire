-- =============================================================================
-- Carte Scolaire : option « Multi-appareil » sur votre serveur Supabase (auto-hébergé)
--
-- À exécuter une fois dans Supabase Studio > SQL Editor (ou psql) sur votre VPS.
-- Crée :
--   - cs_sync_access : comptes qui ont payé l'option (vous les activez à la main) ;
--   - cs_sync_files  : liste des fichiers synchronisés de chaque compte ;
--   - le compartiment de stockage privé « carte-scolaire » (photos et fichiers).
-- Chaque compte ne voit que ses propres données, et seulement si l'option est active.
-- =============================================================================

-- 1. Comptes autorisés -------------------------------------------------------
create table if not exists public.cs_sync_access (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  email      text,
  active     boolean not null default true,
  expires_at timestamptz,
  note       text,
  created_at timestamptz not null default now()
);

alter table public.cs_sync_access enable row level security;

drop policy if exists "cs_access_read_own" on public.cs_sync_access;
create policy "cs_access_read_own" on public.cs_sync_access
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Vrai si le compte connecté a l'option active (et non expirée).
create or replace function public.cs_sync_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.cs_sync_access a
    where a.user_id = (select auth.uid())
      and a.active
      and (a.expires_at is null or a.expires_at > now())
  );
$$;

revoke all on function public.cs_sync_allowed() from public;
grant execute on function public.cs_sync_allowed() to authenticated;

-- 2. Liste des fichiers ------------------------------------------------------
create table if not exists public.cs_sync_files (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  path       text not null,
  hash       text not null,
  size       bigint not null default 0,
  deleted    boolean not null default false,
  device     text,
  updated_at timestamptz not null default now(),
  primary key (user_id, path)
);

alter table public.cs_sync_files enable row level security;

drop policy if exists "cs_files_select" on public.cs_sync_files;
drop policy if exists "cs_files_insert" on public.cs_sync_files;
drop policy if exists "cs_files_update" on public.cs_sync_files;
drop policy if exists "cs_files_delete" on public.cs_sync_files;

create policy "cs_files_select" on public.cs_sync_files for select to authenticated
  using (user_id = (select auth.uid()) and (select public.cs_sync_allowed()));
create policy "cs_files_insert" on public.cs_sync_files for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.cs_sync_allowed()));
create policy "cs_files_update" on public.cs_sync_files for update to authenticated
  using (user_id = (select auth.uid()) and (select public.cs_sync_allowed()))
  with check (user_id = (select auth.uid()) and (select public.cs_sync_allowed()));
create policy "cs_files_delete" on public.cs_sync_files for delete to authenticated
  using (user_id = (select auth.uid()) and (select public.cs_sync_allowed()));

grant select, insert, update, delete on public.cs_sync_files to authenticated;
grant select on public.cs_sync_access to authenticated;

-- 3. Stockage des fichiers ---------------------------------------------------
-- Compartiment privé ; chaque compte écrit dans son dossier <id du compte>/…
insert into storage.buckets (id, name, public, file_size_limit)
values ('carte-scolaire', 'carte-scolaire', false, 52428800)
on conflict (id) do nothing;

drop policy if exists "cs_storage_select" on storage.objects;
drop policy if exists "cs_storage_insert" on storage.objects;
drop policy if exists "cs_storage_update" on storage.objects;
drop policy if exists "cs_storage_delete" on storage.objects;

create policy "cs_storage_select" on storage.objects for select to authenticated
  using (bucket_id = 'carte-scolaire'
         and (storage.foldername(name))[1] = (select auth.uid())::text
         and (select public.cs_sync_allowed()));
create policy "cs_storage_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'carte-scolaire'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.cs_sync_allowed()));
create policy "cs_storage_update" on storage.objects for update to authenticated
  using (bucket_id = 'carte-scolaire'
         and (storage.foldername(name))[1] = (select auth.uid())::text
         and (select public.cs_sync_allowed()))
  with check (bucket_id = 'carte-scolaire'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.cs_sync_allowed()));
create policy "cs_storage_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'carte-scolaire'
         and (storage.foldername(name))[1] = (select auth.uid())::text
         and (select public.cs_sync_allowed()));

-- =============================================================================
-- Activer l'option pour un client (après qu'il a créé son compte dans l'application) :
--
--   insert into public.cs_sync_access (user_id, email, note)
--   select id, email, 'Payé le 14/11/2026' from auth.users where email = 'client@exemple.com'
--   on conflict (user_id) do update set active = true;
--
-- Avec une date de fin :
--   update public.cs_sync_access set expires_at = '2027-11-14' where email = 'client@exemple.com';
--
-- Suspendre :
--   update public.cs_sync_access set active = false where email = 'client@exemple.com';
-- =============================================================================
