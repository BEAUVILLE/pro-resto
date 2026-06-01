-- DIGIY RESTO — rail fiche vitrine
-- Circuit : cockpit.html -> Supabase pending -> admin validation -> site public
-- À exécuter dans Supabase SQL Editor.

create extension if not exists pgcrypto;

-- 1) Table privée des fiches RESTO
create table if not exists public.digiy_resto_fiches (
  id uuid primary key default gen_random_uuid(),

  -- Identité / rattachement pro
  phone_pro text not null,
  slug text not null,

  -- Statut de publication
  status text not null default 'pending'
    check (status in ('pending', 'published', 'rejected', 'archived')),

  -- Fiche vitrine
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

  -- Carte du restaurant : URL uniquement, pas de fichier brut dans la table
  carte_titre text,
  carte_texte text,
  carte_url text,
  carte_photo_url text,

  -- Photos : URL publiques Supabase Storage ou autre URL publique validée
  photo_principale_url text,
  photo_2_url text,
  photo_3_url text,

  -- Données libres pour évolution future sans casser le rail
  payload jsonb not null default '{}'::jsonb,

  -- Validation admin
  admin_note text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  rejected_at timestamptz
);

-- Une fiche active par slug. Les nouvelles soumissions remplacent la fiche du même restaurant.
create unique index if not exists digiy_resto_fiches_slug_uidx
  on public.digiy_resto_fiches(slug);

create index if not exists digiy_resto_fiches_status_idx
  on public.digiy_resto_fiches(status);

create index if not exists digiy_resto_fiches_phone_idx
  on public.digiy_resto_fiches(phone_pro);

create index if not exists digiy_resto_fiches_published_idx
  on public.digiy_resto_fiches(published_at desc)
  where status = 'published';

-- 2) Updated_at automatique
create or replace function public.digiy_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_digiy_resto_fiches_updated_at on public.digiy_resto_fiches;
create trigger trg_digiy_resto_fiches_updated_at
before update on public.digiy_resto_fiches
for each row execute function public.digiy_touch_updated_at();

-- 3) RLS
alter table public.digiy_resto_fiches enable row level security;

-- Nettoyage politiques si relance du script
DROP POLICY IF EXISTS "RESTO public can read published fiches" ON public.digiy_resto_fiches;
DROP POLICY IF EXISTS "RESTO service role full access" ON public.digiy_resto_fiches;

-- Le public lit uniquement les fiches publiées.
create policy "RESTO public can read published fiches"
on public.digiy_resto_fiches
for select
to anon, authenticated
using (status = 'published');

-- Le service role garde la main admin complète.
create policy "RESTO service role full access"
on public.digiy_resto_fiches
for all
to service_role
using (true)
with check (true);

-- 4) Vue publique, propre pour le site DIGIY RESTO
create or replace view public.digiy_resto_fiches_published as
select
  id,
  slug,
  nom_restaurant,
  slogan,
  cuisine,
  ambiance,
  description,
  adresse,
  horaires,
  whatsapp,
  google_maps_url,
  social_url,
  carte_titre,
  carte_texte,
  carte_url,
  carte_photo_url,
  photo_principale_url,
  photo_2_url,
  photo_3_url,
  payload,
  published_at,
  updated_at
from public.digiy_resto_fiches
where status = 'published';

grant select on public.digiy_resto_fiches_published to anon, authenticated;

-- 5) Fonction pro : envoyer / remplacer une fiche en validation
-- Cette fonction accepte seulement des URL en texte pour les photos.
-- Elle ne publie jamais directement : status reste pending.
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
returns table(
  ok boolean,
  fiche_id uuid,
  status text,
  message text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_phone text := regexp_replace(coalesce(p_phone_pro, ''), '\D', '', 'g');
  v_slug text := lower(trim(coalesce(p_slug, '')));
begin
  if length(v_phone) < 8 then
    return query select false, null::uuid, 'error'::text, 'Téléphone pro manquant ou invalide.'::text;
    return;
  end if;

  if v_slug = '' then
    v_slug := 'resto-' || v_phone;
  end if;

  insert into public.digiy_resto_fiches (
    phone_pro,
    slug,
    status,
    nom_restaurant,
    slogan,
    cuisine,
    ambiance,
    description,
    adresse,
    horaires,
    whatsapp,
    google_maps_url,
    social_url,
    carte_titre,
    carte_texte,
    carte_url,
    carte_photo_url,
    photo_principale_url,
    photo_2_url,
    photo_3_url,
    payload,
    submitted_at,
    published_at,
    rejected_at,
    admin_note
  ) values (
    v_phone,
    v_slug,
    'pending',
    nullif(trim(coalesce(p_nom_restaurant, '')), ''),
    nullif(trim(coalesce(p_slogan, '')), ''),
    nullif(trim(coalesce(p_cuisine, '')), ''),
    nullif(trim(coalesce(p_ambiance, '')), ''),
    nullif(trim(coalesce(p_description, '')), ''),
    nullif(trim(coalesce(p_adresse, '')), ''),
    nullif(trim(coalesce(p_horaires, '')), ''),
    nullif(regexp_replace(coalesce(p_whatsapp, ''), '\D', '', 'g'), ''),
    nullif(trim(coalesce(p_google_maps_url, '')), ''),
    nullif(trim(coalesce(p_social_url, '')), ''),
    nullif(trim(coalesce(p_carte_titre, '')), ''),
    nullif(trim(coalesce(p_carte_texte, '')), ''),
    nullif(trim(coalesce(p_carte_url, '')), ''),
    nullif(trim(coalesce(p_carte_photo_url, '')), ''),
    nullif(trim(coalesce(p_photo_principale_url, '')), ''),
    nullif(trim(coalesce(p_photo_2_url, '')), ''),
    nullif(trim(coalesce(p_photo_3_url, '')), ''),
    coalesce(p_payload, '{}'::jsonb),
    now(),
    null,
    null,
    null
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

-- 6) Fonctions admin : à utiliser avec service_role ou depuis un admin protégé
create or replace function public.digiy_admin_publish_resto_fiche(
  p_id uuid,
  p_admin_note text default null
)
returns table(ok boolean, fiche_id uuid, status text, message text)
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.digiy_resto_fiches
  set status = 'published',
      published_at = now(),
      rejected_at = null,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), '')
  where id = p_id
  returning id into p_id;

  if p_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, p_id, 'published'::text, 'Fiche RESTO publiée.'::text;
end;
$$;

create or replace function public.digiy_admin_reject_resto_fiche(
  p_id uuid,
  p_admin_note text default null
)
returns table(ok boolean, fiche_id uuid, status text, message text)
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.digiy_resto_fiches
  set status = 'rejected',
      rejected_at = now(),
      published_at = null,
      admin_note = nullif(trim(coalesce(p_admin_note, '')), '')
  where id = p_id
  returning id into p_id;

  if p_id is null then
    return query select false, null::uuid, 'error'::text, 'Fiche introuvable.'::text;
    return;
  end if;

  return query select true, p_id, 'rejected'::text, 'Fiche RESTO refusée / à corriger.'::text;
end;
$$;

-- On ne donne pas les fonctions admin à anon/authenticated.
revoke all on function public.digiy_admin_publish_resto_fiche(uuid, text) from public, anon, authenticated;
revoke all on function public.digiy_admin_reject_resto_fiche(uuid, text) from public, anon, authenticated;

-- 7) Exemple lecture site public
-- select * from public.digiy_resto_fiches_published order by published_at desc;

-- 8) Exemple envoi fiche côté cockpit.html
-- select * from public.digiy_resto_submit_fiche(
--   p_phone_pro := '221771342889',
--   p_slug := 'resto-221771342889',
--   p_nom_restaurant := 'Le Coin Éthique',
--   p_photo_principale_url := 'https://...supabase.co/storage/v1/object/public/resto/...jpg',
--   p_payload := '{"source":"cockpit.html"}'::jsonb
-- );
