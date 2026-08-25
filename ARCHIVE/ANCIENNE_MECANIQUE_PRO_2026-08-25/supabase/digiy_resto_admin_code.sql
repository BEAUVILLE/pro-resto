-- DIGIY RESTO — admin validation par code hashé
-- À exécuter APRÈS supabase/digiy_resto_fiches.sql
-- Objectif : permettre à une page admin statique de lister/publier/refuser
-- sans exposer la clé service_role dans le navigateur.

create extension if not exists pgcrypto;

-- 1) Table de réglage admin privée
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

-- 2) Installer le code admin RESTO
-- IMPORTANT : remplace CHANGE_ME_RESTO_ADMIN par ton vrai code admin AVANT exécution,
-- ou relance seulement cet update ensuite avec ton code.
insert into public.digiy_admin_settings(key, value)
values ('resto_admin_code_hash', crypt('CHANGE_ME_RESTO_ADMIN', gen_salt('bf')))
on conflict (key) do nothing;

-- Pour changer le code plus tard :
-- update public.digiy_admin_settings
-- set value = crypt('TON_NOUVEAU_CODE_ADMIN', gen_salt('bf')), updated_at = now()
-- where key = 'resto_admin_code_hash';

-- 3) Vérification code admin côté RPC
create or replace function public.digiy_resto_admin_code_ok(p_admin_code text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
begin
  select value into v_hash
  from public.digiy_admin_settings
  where key = 'resto_admin_code_hash';

  if v_hash is null then
    return false;
  end if;

  return v_hash = crypt(coalesce(p_admin_code, ''), v_hash);
end;
$$;

revoke all on function public.digiy_resto_admin_code_ok(text) from public, anon, authenticated;

-- 4) Lister les fiches RESTO pour admin
create or replace function public.digiy_resto_admin_list_fiches(
  p_admin_code text,
  p_status text default 'pending'
)
returns table(
  id uuid,
  slug text,
  phone_pro text,
  status text,
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
  admin_note text,
  submitted_at timestamptz,
  published_at timestamptz,
  rejected_at timestamptz,
  updated_at timestamptz
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
  select
    f.id,
    f.slug,
    f.phone_pro,
    f.status,
    f.nom_restaurant,
    f.slogan,
    f.cuisine,
    f.ambiance,
    f.description,
    f.adresse,
    f.horaires,
    f.whatsapp,
    f.google_maps_url,
    f.social_url,
    f.carte_titre,
    f.carte_texte,
    f.carte_url,
    f.carte_photo_url,
    f.photo_principale_url,
    f.photo_2_url,
    f.photo_3_url,
    f.admin_note,
    f.submitted_at,
    f.published_at,
    f.rejected_at,
    f.updated_at
  from public.digiy_resto_fiches f
  where (p_status is null or p_status = 'all' or f.status = p_status)
  order by f.submitted_at desc nulls last, f.updated_at desc;
end;
$$;

grant execute on function public.digiy_resto_admin_list_fiches(text, text) to anon, authenticated;

-- 5) Publier une fiche par code admin
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
declare
  v_id uuid;
begin
  if not public.digiy_resto_admin_code_ok(p_admin_code) then
    return query select false, null::uuid, 'error'::text, 'Code admin incorrect.'::text;
    return;
  end if;

  update public.digiy_resto_fiches
  set status = 'published',
      published_at = now(),
      rejected_at = null,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), '')
  where id = p_id
  returning id into v_id;

  if v_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, v_id, 'published'::text, 'Fiche RESTO publiée.'::text;
end;
$$;

grant execute on function public.digiy_resto_admin_publish_fiche(text, uuid, text) to anon, authenticated;

-- 6) Refuser / renvoyer correction
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
declare
  v_id uuid;
begin
  if not public.digiy_resto_admin_code_ok(p_admin_code) then
    return query select false, null::uuid, 'error'::text, 'Code admin incorrect.'::text;
    return;
  end if;

  update public.digiy_resto_fiches
  set status = 'rejected',
      rejected_at = now(),
      published_at = null,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), '')
  where id = p_id
  returning id into v_id;

  if v_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, v_id, 'rejected'::text, 'Fiche RESTO renvoyée à correction.'::text;
end;
$$;

grant execute on function public.digiy_resto_admin_reject_fiche(text, uuid, text) to anon, authenticated;
