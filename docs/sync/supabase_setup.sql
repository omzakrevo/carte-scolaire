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

-- 4. Activation automatique par la licence ----------------------------------
-- L'application envoie son code de licence (signé par la clé de l'administrateur).
-- Si la signature est bonne et que la licence contient le module « sync », le compte
-- est activé jusqu'à la fin de la licence. Vérification Ed25519 par pgsodium.
create extension if not exists pgsodium;

alter table public.cs_sync_access add column if not exists blocked boolean not null default false;
alter table public.cs_sync_access add column if not exists licenses text[] not null default '{}';

create or replace function public.cs_b64url(t text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select decode(rpad(translate(t, '-_', '+/'), ((length(t) + 3) / 4) * 4, '='), 'base64');
$$;

create or replace function public.cs_register_license(code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  admin_key constant bytea := decode('9z6fiwSh9JJ+XGPnVLNmzzVsVMoDjZrj444y0RCO23g=', 'base64');
  parts text[];
  payload text;
  f text[];
  ok boolean;
  ends timestamptz;
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'non connecté'; end if;
  parts := string_to_array(regexp_replace(code, '\s', '', 'g'), '.');
  if array_length(parts, 1) <> 2 then raise exception 'code invalide'; end if;
  payload := convert_from(public.cs_b64url(parts[1]), 'UTF8');
  ok := pgsodium.crypto_sign_verify_detached(public.cs_b64url(parts[2]), convert_to(payload, 'UTF8'), admin_key);
  if not ok then raise exception 'signature invalide'; end if;
  f := string_to_array(payload, '|');
  if f[1] <> 'CS1' or array_length(f, 1) < 7 then raise exception 'licence sans modules'; end if;
  if not ('sync' = any (string_to_array(f[7], ','))) then raise exception 'module multi-appareil absent'; end if;
  if f[5] <> '0' then
    ends := to_date(f[5], 'YYYYMMDD') + interval '1 day';
    if ends < now() then raise exception 'licence expirée'; end if;
  end if;
  insert into public.cs_sync_access as a (user_id, email, active, expires_at, licenses, note)
  values (uid, (select email from auth.users where id = uid), true, ends, array[f[2]], 'licence ' || f[2])
  on conflict (user_id) do update set
    active = true,
    licenses = (select array(select distinct unnest(a.licenses || excluded.licenses))),
    expires_at = case when a.expires_at is null and a.licenses <> '{}' then null
                      when excluded.expires_at is null then null
                      else greatest(a.expires_at, excluded.expires_at) end;
  return jsonb_build_object('active', true, 'expires_at', ends);
end;
$$;

revoke all on function public.cs_register_license(text) from public;
grant execute on function public.cs_register_license(text) to authenticated;

-- Un compte bloqué par l'administrateur n'a plus accès, même avec une licence.
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
      and a.active and not a.blocked
      and (a.expires_at is null or a.expires_at > now())
  );
$$;

-- 5. Ajout d'un appareil par code -------------------------------------------
-- Le premier appareil dépose les identifiants du compte, chiffrés avec le code affiché
-- à l'écran (le serveur ne peut pas les lire). Le second appareil les récupère une seule
-- fois avec ce code, dans les 15 minutes.
create table if not exists public.cs_pairing (
  id         text primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  blob       text not null,
  expires_at timestamptz not null default now() + interval '15 minutes'
);
alter table public.cs_pairing enable row level security;

create or replace function public.cs_pair_put(pair_id text, data text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'non connecté'; end if;
  if length(pair_id) <> 64 or length(data) > 4000 then raise exception 'code invalide'; end if;
  delete from public.cs_pairing where expires_at < now() or user_id = auth.uid();
  insert into public.cs_pairing (id, user_id, blob) values (pair_id, auth.uid(), data);
end;
$$;

create or replace function public.cs_pair_take(pair_id text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  b text;
begin
  delete from public.cs_pairing where id = pair_id and expires_at > now() returning blob into b;
  return b;
end;
$$;

revoke all on function public.cs_pair_put(text, text) from public;
revoke all on function public.cs_pair_take(text) from public;
grant execute on function public.cs_pair_put(text, text) to authenticated;
grant execute on function public.cs_pair_take(text) to anon, authenticated;

-- =============================================================================
-- L'activation est automatique avec une licence contenant « Multi-appareil ».
-- Activer à la main un client (sans licence adaptée) :
--
--   insert into public.cs_sync_access (user_id, email, note)
--   select id, email, 'Payé le 14/11/2026' from auth.users where email = 'client@exemple.com'
--   on conflict (user_id) do update set active = true;
--
-- Avec une date de fin :
--   update public.cs_sync_access set expires_at = '2027-11-14' where email = 'client@exemple.com';
--
-- Bloquer (même avec une licence valide) :
--   update public.cs_sync_access set blocked = true where email = 'client@exemple.com';
-- =============================================================================
