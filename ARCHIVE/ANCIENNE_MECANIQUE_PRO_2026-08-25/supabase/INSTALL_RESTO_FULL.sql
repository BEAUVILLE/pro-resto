-- DIGIY RESTO — INSTALLATION COMPLÈTE
-- Rail : cockpit.html -> Supabase pending -> admin validation -> public.html
-- À copier-coller en UNE FOIS dans Supabase SQL Editor.
-- IMPORTANT : remplace CHANGE_ME_RESTO_ADMIN par ton vrai code admin avant exécution.

create extension if not exists pgcrypto;

-- =========================================================
-- 1) TABLE FICHES RESTO
-- =========================================================
create table if not exists public.digiy_resto_fiches (
  id uuid primary key default gen_random_uuid(),
  phone_pro text not null,
  slug text not null,
  status text not null default 'pending' check (status in ('pending','published','rejected','archived')),
  nom_restaurant text,
  slogan text,
  cuisine text,
  ambiance text,
  description text,
  adresse text,
  horaires text,
  whatsapp text,
  google_maps_url text,
  social_url text,
  carte_titre text,
  carte_texte text,
  carte_url text,
  carte_photo_url text,
  photo_principale_url text,
  photo_2_url text,
  photo_3_url text,
  payload jsonb not null default '{}'::jsonb,
  admin_note text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  rejected_at timestamptz
);

create unique index if not exists digiy_resto_fiches_slug_uidx on public.digiy_resto_fiches(slug);
create index if not exists digiy_resto_fiches_status_idx on public.digiy_resto_fiches(status);
create index if not exists digiy_resto_fiches_phone_idx on public.digiy_resto_fiches(phone_pro);
create index if not exists digiy_resto_fiches_published_idx on public.digiy_resto_fiches(published_at desc) where status='published';

create or replace function public.digiy_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_digiy_resto_fiches_updated_at on public.digiy_resto_fiches;
create trigger trg_digiy_resto_fiches_updated_at
before update on public.digiy_resto_fiches
for each row execute function public.digiy_touch_updated_at();

-- =========================================================
-- 2) SÉCURITÉ / LECTURE PUBLIQUE
-- =========================================================
alter table public.digiy_resto_fiches enable row level security;

drop policy if exists "RESTO public can read published fiches" on public.digiy_resto_fiches;
drop policy if exists "RESTO service role full access" on public.digiy_resto_fiches;

create policy "RESTO public can read published fiches"
on public.digiy_resto_fiches
for select
to anon, authenticated
using (status = 'published');

create policy "RESTO service role full access"
on public.digiy_resto_fiches
for all
to service_role
using (true)
with check (true);

create or replace view public.digiy_resto_fiches_published as
select
  id, slug, nom_restaurant, slogan, cuisine, ambiance, description,
  adresse, horaires, whatsapp, google_maps_url, social_url,
  carte_titre, carte_texte, carte_url, carte_photo_url,
  photo_principale_url, photo_2_url, photo_3_url,
  payload, published_at, updated_at
from public.digiy_resto_fiches
where status = 'published';

grant select on public.digiy_resto_fiches_published to anon, authenticated;

-- =========================================================
-- 3) ENVOI FICHE PRO -> PENDING
-- =========================================================
create or replace function public.digiy_resto_submit_fiche(
  p_phone_pro text,
  p_slug text,
  p_nom_restaurant text default null,
  p_slogan text default null,
  p_cuisine text default null,
  p_ambiance text default null,
  p_description text default null,
  p_adresse text default null,
  p_horaires text default null,
  p_whatsapp text default null,
  p_google_maps_url text default null,
  p_social_url text default null,
  p_carte_titre text default null,
  p_carte_texte text default null,
  p_carte_url text default null,
  p_carte_photo_url text default null,
  p_photo_principale_url text default null,
  p_photo_2_url text default null,
  p_photo_3_url text default null,
  p_payload jsonb default '{}'::jsonb
)
returns table(ok boolean, fiche_id uuid, status text, message text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_phone text := regexp_replace(coalesce(p_phone_pro,''), '\D', '', 'g');
  v_slug text := lower(trim(coalesce(p_slug,'')));
begin
  if length(v_phone) < 8 then
    return query select false, null::uuid, 'error'::text, 'Téléphone pro manquant ou invalide.'::text;
    return;
  end if;

  if v_slug = '' then
    v_slug := 'resto-' || v_phone;
  end if;

  insert into public.digiy_resto_fiches(
    phone_pro, slug, status, nom_restaurant, slogan, cuisine, ambiance,
    description, adresse, horaires, whatsapp, google_maps_url, social_url,
    carte_titre, carte_texte, carte_url, carte_photo_url,
    photo_principale_url, photo_2_url, photo_3_url, payload,
    submitted_at, published_at, rejected_at, admin_note
  ) values (
    v_phone, v_slug, 'pending',
    nullif(trim(coalesce(p_nom_restaurant,'')),''),
    nullif(trim(coalesce(p_slogan,'')),''),
    nullif(trim(coalesce(p_cuisine,'')),''),
    nullif(trim(coalesce(p_ambiance,'')),''),
    nullif(trim(coalesce(p_description,'')),''),
    nullif(trim(coalesce(p_adresse,'')),''),
    nullif(trim(coalesce(p_horaires,'')),''),
    nullif(regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g'),''),
    nullif(trim(coalesce(p_google_maps_url,'')),''),
    nullif(trim(coalesce(p_social_url,'')),''),
    nullif(trim(coalesce(p_carte_titre,'')),''),
    nullif(trim(coalesce(p_carte_texte,'')),''),
    nullif(trim(coalesce(p_carte_url,'')),''),
    nullif(trim(coalesce(p_carte_photo_url,'')),''),
    nullif(trim(coalesce(p_photo_principale_url,'')),''),
    nullif(trim(coalesce(p_photo_2_url,'')),''),
    nullif(trim(coalesce(p_photo_3_url,'')),''),
    coalesce(p_payload,'{}'::jsonb),
    now(), null, null, null
  )
  on conflict (slug) do update set
    phone_pro = excluded.phone_pro,
    status = 'pending',
    nom_restaurant = excluded.nom_restaurant,
    slogan = excluded.slogan,
    cuisine = excluded.cuisine,
    ambiance = excluded.ambiance,
    description = excluded.description,
    adresse = excluded.adresse,
    horaires = excluded.horaires,
    whatsapp = excluded.whatsapp,
    google_maps_url = excluded.google_maps_url,
    social_url = excluded.social_url,
    carte_titre = excluded.carte_titre,
    carte_texte = excluded.carte_texte,
    carte_url = excluded.carte_url,
    carte_photo_url = excluded.carte_photo_url,
    photo_principale_url = excluded.photo_principale_url,
    photo_2_url = excluded.photo_2_url,
    photo_3_url = excluded.photo_3_url,
    payload = excluded.payload,
    submitted_at = now(),
    published_at = null,
    rejected_at = null,
    admin_note = null
  returning id into v_id;

  return query select true, v_id, 'pending'::text, 'Fiche RESTO envoyée à validation DIGIY.'::text;
end;
$$;

grant execute on function public.digiy_resto_submit_fiche(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb
) to anon, authenticated;

-- =========================================================
-- 4) CODE ADMIN HASHÉ
-- =========================================================
create table if not exists public.digiy_admin_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

alter table public.digiy_admin_settings enable row level security;

drop policy if exists "DIGIY admin settings service role only" on public.digiy_admin_settings;
create policy "DIGIY admin settings service role only"
on public.digiy_admin_settings
for all
to service_role
using (true)
with check (true);

insert into public.digiy_admin_settings(key,value)
values ('resto_admin_code_hash', crypt('CHANGE_ME_RESTO_ADMIN', gen_salt('bf')))
on conflict (key) do update set value = excluded.value, updated_at = now();

create or replace function public.digiy_resto_admin_code_ok(p_admin_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_hash text;
begin
  select value into v_hash from public.digiy_admin_settings where key='resto_admin_code_hash';
  if v_hash is null then return false; end if;
  return v_hash = crypt(coalesce(p_admin_code,''), v_hash);
end;
$$;

revoke all on function public.digiy_resto_admin_code_ok(text) from public, anon, authenticated;

-- =========================================================
-- 5) ADMIN LIST / PUBLISH / REJECT PAR RPC
-- =========================================================
create or replace function public.digiy_resto_admin_list_fiches(
  p_admin_code text,
  p_status text default 'pending'
)
returns table(
  id uuid, slug text, phone_pro text, status text,
  nom_restaurant text, slogan text, cuisine text, ambiance text,
  description text, adresse text, horaires text, whatsapp text,
  google_maps_url text, social_url text,
  carte_titre text, carte_texte text, carte_url text, carte_photo_url text,
  photo_principale_url text, photo_2_url text, photo_3_url text,
  admin_note text, submitted_at timestamptz, published_at timestamptz,
  rejected_at timestamptz, updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.digiy_resto_admin_code_ok(p_admin_code) then
    raise exception 'Code admin incorrect.';
  end if;

  return query
  select f.id,f.slug,f.phone_pro,f.status,f.nom_restaurant,f.slogan,f.cuisine,f.ambiance,
         f.description,f.adresse,f.horaires,f.whatsapp,f.google_maps_url,f.social_url,
         f.carte_titre,f.carte_texte,f.carte_url,f.carte_photo_url,
         f.photo_principale_url,f.photo_2_url,f.photo_3_url,
         f.admin_note,f.submitted_at,f.published_at,f.rejected_at,f.updated_at
  from public.digiy_resto_fiches f
  where (p_status is null or p_status='all' or f.status=p_status)
  order by f.submitted_at desc nulls last, f.updated_at desc;
end;
$$;

grant execute on function public.digiy_resto_admin_list_fiches(text,text) to anon, authenticated;

create or replace function public.digiy_resto_admin_publish_fiche(
  p_admin_code text,
  p_id uuid,
  p_admin_note text default null
)
returns table(ok boolean, fiche_id uuid, status text, message text)
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.digiy_resto_admin_code_ok(p_admin_code) then
    return query select false, null::uuid, 'error'::text, 'Code admin incorrect.'::text;
    return;
  end if;

  update public.digiy_resto_fiches
  set status='published', published_at=now(), rejected_at=null,
      admin_note=nullif(trim(coalesce(p_admin_note,'')),'')
  where id=p_id
  returning id into v_id;

  if v_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, v_id, 'published'::text, 'Fiche RESTO publiée.'::text;
end;
$$;

grant execute on function public.digiy_resto_admin_publish_fiche(text,uuid,text) to anon, authenticated;

create or replace function public.digiy_resto_admin_reject_fiche(
  p_admin_code text,
  p_id uuid,
  p_admin_note text default null
)
returns table(ok boolean, fiche_id uuid, status text, message text)
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.digiy_resto_admin_code_ok(p_admin_code) then
    return query select false, null::uuid, 'error'::text, 'Code admin incorrect.'::text;
    return;
  end if;

  update public.digiy_resto_fiches
  set status='rejected', rejected_at=now(), published_at=null,
      admin_note=nullif(trim(coalesce(p_admin_note,'')),'')
  where id=p_id
  returning id into v_id;

  if v_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, v_id, 'rejected'::text, 'Fiche RESTO renvoyée à correction.'::text;
end;
$$;

grant execute on function public.digiy_resto_admin_reject_fiche(text,uuid,text) to anon, authenticated;

-- =========================================================
-- 6) RECHARGE CACHE API SUPABASE
-- =========================================================
notify pgrst, 'reload schema';

-- Contrôle rapide après exécution :
-- select * from public.digiy_resto_fiches_published;
