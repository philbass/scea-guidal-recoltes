-- =====================================================================
--  SCEA Guidal · Mise à jour 02 : modes de paie, tarifs, horaires, SMIC
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run,
--  juste avant de publier la nouvelle version de l'application.
--
--  ATTENTION : efface tous les anciens produits (Radis en botte,
--  Choux en colis) ET toutes les saisies de récolte déjà faites.
--  Les saisonniers et les comptes sont conservés.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Effacer les saisies d'essai et les anciens produits
-- ---------------------------------------------------------------------
delete from public.recoltes;
delete from public.legumes;

-- ---------------------------------------------------------------------
-- 2. Produits : mode de paie et nom en portugais (l'unité disparaît)
-- ---------------------------------------------------------------------
alter table public.legumes drop column if exists unite;
alter table public.legumes add column if not exists mode text not null default 'colis'
  check (mode in ('colis', 'unite', 'heure'));
alter table public.legumes add column if not exists nom_pt text;

-- ---------------------------------------------------------------------
-- 3. Nouvelles tables
-- ---------------------------------------------------------------------

-- Prix d'un produit à partir d'une date (l'ancien prix reste valable pour les jours passés)
create table if not exists public.tarifs (
  id         bigint generated always as identity primary key,
  legume_id  bigint not null references public.legumes (id) on delete cascade,
  prix       numeric(10, 3) not null check (prix >= 0),
  depuis     date not null,
  unique (legume_id, depuis)
);

-- SMIC horaire brut à partir d'une date
create table if not exists public.smic (
  depuis date primary key,
  taux   numeric(10, 3) not null check (taux > 0)
);

-- Horaires d'un saisonnier pour une journée (matin et après-midi)
create table if not exists public.presences (
  id            bigint generated always as identity primary key,
  date          date not null,
  saisonnier_id bigint not null references public.saisonniers (id),
  matin_debut   time,
  matin_fin     time,
  am_debut      time,
  am_fin        time,
  saisi_par     uuid references public.profils (id),
  corrige_par   uuid references public.profils (id),
  modifie_le    timestamptz not null default now(),
  unique (date, saisonnier_id),
  check ((matin_debut is null) = (matin_fin is null) and (matin_debut is null or matin_fin > matin_debut)),
  check ((am_debut is null) = (am_fin is null) and (am_debut is null or am_fin > am_debut))
);
create index if not exists presences_date_idx on public.presences (date);

drop trigger if exists presences_auteur on public.presences;
create trigger presences_auteur
  before insert or update on public.presences
  for each row execute function public.recolte_auteur();

-- ---------------------------------------------------------------------
-- 4. Enregistrer une journée complète (quantités + horaires) en une fois
-- ---------------------------------------------------------------------
create or replace function public.enregistrer_journee(p_date date, p_saisonnier bigint, p_quantites jsonb, p_horaires jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare
  md time := nullif(p_horaires ->> 'matin_debut', '')::time;
  mf time := nullif(p_horaires ->> 'matin_fin', '')::time;
  ad time := nullif(p_horaires ->> 'am_debut', '')::time;
  af time := nullif(p_horaires ->> 'am_fin', '')::time;
begin
  perform public.enregistrer_saisie(p_date, p_saisonnier, coalesce(p_quantites, '{}'::jsonb));
  if md is null and mf is null and ad is null and af is null then
    delete from public.presences where date = p_date and saisonnier_id = p_saisonnier;
  else
    insert into public.presences (date, saisonnier_id, matin_debut, matin_fin, am_debut, am_fin)
    values (p_date, p_saisonnier, md, mf, ad, af)
    on conflict (date, saisonnier_id) do update
      set matin_debut = excluded.matin_debut, matin_fin = excluded.matin_fin,
          am_debut = excluded.am_debut, am_fin = excluded.am_fin
      where (public.presences.matin_debut, public.presences.matin_fin, public.presences.am_debut, public.presences.am_fin)
            is distinct from (excluded.matin_debut, excluded.matin_fin, excluded.am_debut, excluded.am_fin);
  end if;
end $$;

revoke all on function public.enregistrer_journee(date, bigint, jsonb, jsonb) from public, anon;
grant execute on function public.enregistrer_journee(date, bigint, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Droits d'accès
--    tarifs et SMIC : responsable seulement (le chef ne voit jamais les prix)
--    horaires       : mêmes règles que les récoltes (chef : 7 derniers jours)
-- ---------------------------------------------------------------------
grant select, insert, update, delete on public.tarifs, public.smic, public.presences to authenticated;
grant usage, select on all sequences in schema public to authenticated;

alter table public.tarifs    enable row level security;
alter table public.smic      enable row level security;
alter table public.presences enable row level security;

drop policy if exists "tarifs_responsable" on public.tarifs;
create policy "tarifs_responsable" on public.tarifs for all to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "smic_responsable" on public.smic;
create policy "smic_responsable" on public.smic for all to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "presences_lecture" on public.presences;
create policy "presences_lecture" on public.presences for select to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7));
drop policy if exists "presences_ajout" on public.presences;
create policy "presences_ajout" on public.presences for insert to authenticated
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between current_date - 7 and current_date));
drop policy if exists "presences_modif" on public.presences;
create policy "presences_modif" on public.presences for update to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7))
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between current_date - 7 and current_date));
drop policy if exists "presences_suppression" on public.presences;
create policy "presences_suppression" on public.presences for delete to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7));

-- ---------------------------------------------------------------------
-- 6. Temps réel
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.presences;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.tarifs;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.smic;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 7. Les 17 produits (les prix se saisissent ensuite dans « Produits et tarifs »)
-- ---------------------------------------------------------------------
insert into public.legumes (nom, nom_pt, mode, ordre) values
  ('Radis',          'Rabanete',      'colis', 1),
  ('Oignons blancs', 'Cebola branca', 'colis', 2),
  ('Oignons rouges', 'Cebola roxa',   'colis', 3),
  ('Ciboule',        'Cebolinho',     'colis', 4),
  ('Persil',         'Salsa',         'colis', 5),
  ('Persil scotch',  'Salsa scotch',  'unite', 6),
  ('Épluchage',      'Descasque',     'heure', 7),
  ('Plantation',     'Plantação',     'heure', 8),
  ('Binage',         'Sacha',         'heure', 9),
  ('Chou-fleur',     'Couve-flor',    'heure', 10),
  ('Chou vert',      'Couve verde',   'heure', 11),
  ('Chou blanc',     'Couve branca',  'heure', 12),
  ('Chou rouge',     'Couve roxa',    'heure', 13),
  ('Courgette',      'Curgete',       'heure', 14),
  ('Panais',         'Pastinaca',     'heure', 15),
  ('Céleri branche', 'Aipo',          'heure', 16),
  ('Brocoli',        'Brócolos',      'heure', 17);

commit;
