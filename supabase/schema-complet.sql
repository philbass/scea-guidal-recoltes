-- =====================================================================
--  SCEA Guidal · Suivi des récoltes — base COMPLÈTE pour une NOUVELLE installation
--  À coller en une seule fois dans Supabase > SQL Editor > New query > Run.
--
--  Ce fichier donne directement la base à jour (équivalent de schema.sql suivi
--  de maj-01 à maj-07). Pour une base DÉJÀ installée, ne l'utilisez pas :
--  exécutez seulement les fichiers maj-0N qui manquent.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

begin;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Comptes prévus par le responsable, en attente de création (valables 15 minutes)
create table if not exists public.invitations (
  identifiant text primary key check (identifiant ~ '^[a-z0-9._-]{2,40}$'),
  nom         text not null,
  role        text not null check (role in ('chef', 'responsable')),
  created_at  timestamptz not null default now()
);

-- Utilisateurs de l'application (chefs d'équipe et responsables)
create table if not exists public.profils (
  id          uuid primary key references auth.users (id) on delete cascade,
  identifiant text not null unique,
  nom         text not null,
  role        text not null check (role in ('chef', 'responsable')),
  actif       boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.saisonniers (
  id         bigint generated always as identity primary key,
  nom        text not null,
  prenom     text not null,
  actif      boolean not null default true,
  created_at timestamptz not null default now()
);

-- Produits et tâches : mode de paie au colis, à l'unité ou à l'heure
create table if not exists public.legumes (
  id               bigint generated always as identity primary key,
  nom              text not null,
  actif            boolean not null default true,
  ordre            integer not null default 0,
  mode             text not null default 'colis' check (mode in ('colis', 'unite', 'heure')),
  nom_pt           text,
  bottes_par_colis integer not null default 1 check (bottes_par_colis > 0)
);

-- Une ligne = une quantité d'un produit pour un saisonnier, un jour, le matin ou l'après-midi
create table if not exists public.recoltes (
  id            bigint generated always as identity primary key,
  date          date not null,
  saisonnier_id bigint not null references public.saisonniers (id) on delete cascade,
  legume_id     bigint not null references public.legumes (id),
  quantite      numeric(10, 2) not null check (quantite >= 0),
  saisi_par     uuid references public.profils (id),
  corrige_par   uuid references public.profils (id),
  modifie_le    timestamptz not null default now(),
  periode       text not null default 'matin' check (periode in ('matin', 'am')),
  constraint recoltes_jour_periode_unique unique (date, saisonnier_id, legume_id, periode)
);
create index if not exists recoltes_date_idx on public.recoltes (date);

-- Prix d'un produit (et bottes par colis) à partir d'une date
create table if not exists public.tarifs (
  id               bigint generated always as identity primary key,
  legume_id        bigint not null references public.legumes (id) on delete cascade,
  prix             numeric(10, 3) not null check (prix >= 0),
  depuis           date not null,
  bottes_par_colis integer check (bottes_par_colis > 0),
  unique (legume_id, depuis)
);

-- SMIC horaire brut à partir d'une date
create table if not exists public.smic (
  depuis date primary key,
  taux   numeric(10, 3) not null check (taux > 0)
);

-- Horaires d'un saisonnier pour une journée (matin et après-midi) et absences
create table if not exists public.presences (
  id            bigint generated always as identity primary key,
  date          date not null,
  saisonnier_id bigint not null references public.saisonniers (id) on delete cascade,
  matin_debut   time,
  matin_fin     time,
  am_debut      time,
  am_fin        time,
  saisi_par     uuid references public.profils (id),
  corrige_par   uuid references public.profils (id),
  modifie_le    timestamptz not null default now(),
  matin_absent  boolean not null default false,
  am_absent     boolean not null default false,
  unique (date, saisonnier_id),
  check ((matin_debut is null) = (matin_fin is null) and (matin_debut is null or matin_fin > matin_debut)),
  check ((am_debut is null) = (am_fin is null) and (am_debut is null or am_fin > am_debut))
);
create index if not exists presences_date_idx on public.presences (date);

-- Journal des modifications des saisies (lu par le responsable)
create table if not exists public.journal_saisies (
  id            bigint generated always as identity primary key,
  quand         timestamptz not null default now(),
  par           uuid,
  table_nom     text not null,
  action        text not null,
  date          date,
  saisonnier_id bigint,
  periode       text,
  legume_id     bigint,
  avant         jsonb,
  apres         jsonb
);
create index if not exists journal_saisies_jour_idx on public.journal_saisies (date, saisonnier_id);

-- ---------------------------------------------------------------------
-- 2. Fonctions
-- ---------------------------------------------------------------------

-- Rôle de la personne connectée ('chef', 'responsable' ou null si compte inactif / inconnu)
create or replace function public.mon_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profils where id = auth.uid() and actif
$$;


-- « Aujourd'hui » à l'heure de Paris
create or replace function public.jour_paris()
returns date language sql stable set search_path = public as $$
  select (now() at time zone 'Europe/Paris')::date
$$;


-- Crée le profil quand un compte invité est créé ; refuse toute autre inscription
create or replace function public.creer_profil()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  inv     public.invitations;
  ident   text := lower(split_part(new.email, '@', 1));
  domaine text := lower(split_part(new.email, '@', 2));
  premier boolean;
begin
  -- tant qu'aucun responsable n'existe (première installation), l'invitation « admin » reste valable sans limite de temps
  select not exists (select 1 from public.profils where role = 'responsable') into premier;

  select * into inv from public.invitations
   where identifiant = ident
     and (premier or created_at > now() - interval '15 minutes');

  if not found or domaine <> 'scea-guidal.app' then
    raise exception 'Invitation absente ou expirée : créez le compte depuis l''onglet Équipe de l''application';
  end if;

  insert into public.profils (id, identifiant, nom, role)
  values (new.id, ident, inv.nom, inv.role)
  on conflict (id) do nothing;
  delete from public.invitations where identifiant = ident;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.creer_profil();

-- Note automatiquement qui a saisi et qui a corrigé
create or replace function public.recolte_auteur()
returns trigger language plpgsql set search_path = public as $$
begin
  new.modifie_le := now();
  if tg_op = 'INSERT' then
    new.saisi_par := auth.uid();
    new.corrige_par := null;
  else
    new.saisi_par := old.saisi_par;
    new.corrige_par := case when auth.uid() is distinct from old.saisi_par then auth.uid() else old.corrige_par end;
  end if;
  return new;
end $$;

drop trigger if exists recoltes_auteur on public.recoltes;
create trigger recoltes_auteur
  before insert or update on public.recoltes
  for each row execute function public.recolte_auteur();
drop trigger if exists presences_auteur on public.presences;
create trigger presences_auteur
  before insert or update on public.presences
  for each row execute function public.recolte_auteur();

-- Journal des modifications
create or replace function public.journaliser()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  r jsonb := to_jsonb(coalesce(new, old));
begin
  -- une mise à jour qui ne change que la date de modification n'est pas notée
  if tg_op = 'UPDATE' and (to_jsonb(new) - 'modifie_le' - 'corrige_par') = (to_jsonb(old) - 'modifie_le' - 'corrige_par') then
    return new;
  end if;
  insert into public.journal_saisies (par, table_nom, action, date, saisonnier_id, periode, legume_id, avant, apres)
  values (auth.uid(), tg_table_name, tg_op, (r ->> 'date')::date, (r ->> 'saisonnier_id')::bigint, r ->> 'periode',
          (r ->> 'legume_id')::bigint,
          case when tg_op = 'INSERT' then null else to_jsonb(old) end,
          case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end $$;

drop trigger if exists recoltes_journal on public.recoltes;
create trigger recoltes_journal
  after insert or update or delete on public.recoltes
  for each row execute function public.journaliser();
drop trigger if exists presences_journal on public.presences;
create trigger presences_journal
  after insert or update or delete on public.presences
  for each row execute function public.journaliser();

-- Le responsable change le mot de passe d'un utilisateur
create or replace function public.changer_mot_de_passe(p_user uuid, p_mdp text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if coalesce(public.mon_role(), '') <> 'responsable' then
    raise exception 'Réservé au responsable';
  end if;
  if length(p_mdp) < 6 then
    raise exception 'Le mot de passe doit faire au moins 6 caractères';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_mdp, extensions.gen_salt('bf')),
         updated_at = now()
   where id = p_user;
end $$;

-- Le responsable change l'identifiant de connexion d'un utilisateur
create or replace function public.changer_identifiant(p_user uuid, p_ident text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare
  v_domaine text;
  v_email   text;
begin
  if coalesce(public.mon_role(), '') <> 'responsable' then
    raise exception 'Réservé au responsable';
  end if;
  p_ident := lower(trim(p_ident));
  if p_ident !~ '^[a-z0-9._-]{2,40}$' then
    raise exception 'Identifiant invalide : lettres minuscules, chiffres, point ou tiret';
  end if;
  select split_part(email, '@', 2) into v_domaine from auth.users where id = p_user;
  if v_domaine is null or v_domaine = '' then
    raise exception 'Compte introuvable';
  end if;
  v_email := p_ident || '@' || v_domaine;
  if exists (select 1 from public.profils where identifiant = p_ident and id <> p_user)
     or exists (select 1 from auth.users where lower(email) = v_email and id <> p_user) then
    raise exception 'Cet identifiant existe déjà';
  end if;
  update auth.users set email = v_email, updated_at = now() where id = p_user;
  update auth.identities
     set identity_data = jsonb_set(identity_data, '{email}', to_jsonb(v_email)), updated_at = now()
   where user_id = p_user and provider = 'email';
  update public.profils set identifiant = p_ident where id = p_user;
end $$;

-- Saisie d'une demi-journée (horaires ou absence + quantités), avec les contrôles
create or replace function public.enregistrer_demi_journee(
  p_date date, p_saisonnier bigint, p_periode text,
  p_debut text, p_fin text, p_absent boolean, p_quantites jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare
  d   time := nullif(p_debut, '')::time;
  f   time := nullif(p_fin, '')::time;
  abs boolean := coalesce(p_absent, false);
  q   jsonb := coalesce(p_quantites, '{}'::jsonb);
  k   text;
  v   numeric;
  hh  numeric;
begin
  if p_periode not in ('matin', 'am') then
    raise exception 'Période invalide';
  end if;
  if p_date > public.jour_paris() then
    raise exception 'Impossible d''enregistrer une saisie à une date future';
  end if;
  if abs then
    d := null; f := null;
  else
    if exists (select 1 from jsonb_each_text(q) where value::numeric < 0) then
      raise exception 'Une quantité négative est impossible';
    end if;
    if exists (select 1 from jsonb_each_text(q) where value::numeric > 0) and (d is null or f is null) then
      raise exception 'Horaires obligatoires pour enregistrer des quantités';
    end if;
    if (d is null) <> (f is null) then
      raise exception 'Horaires incomplets';
    end if;
    if d is not null and f <= d then
      raise exception 'L''heure de fin doit être après l''heure de début';
    end if;
    select coalesce(sum(x.value::numeric), 0) into hh
      from jsonb_each_text(q) x join public.legumes l on l.id = x.key::bigint
     where l.mode = 'heure' and x.value::numeric > 0;
    if d is not null and hh > extract(epoch from (f - d)) / 3600 + 0.0001 then
      raise exception 'Les heures à l''heure dépassent la présence';
    end if;
  end if;

  -- quantités de cette demi-journée
  for k, v in select key, value::numeric from jsonb_each_text(q) loop
    if v > 0 and not abs then
      insert into public.recoltes (date, saisonnier_id, legume_id, quantite, periode)
      values (p_date, p_saisonnier, k::bigint, v, p_periode)
      on conflict (date, saisonnier_id, legume_id, periode)
      do update set quantite = excluded.quantite
      where public.recoltes.quantite is distinct from excluded.quantite;
    else
      delete from public.recoltes
      where date = p_date and saisonnier_id = p_saisonnier and legume_id = k::bigint and periode = p_periode;
    end if;
  end loop;
  if abs then
    delete from public.recoltes where date = p_date and saisonnier_id = p_saisonnier and periode = p_periode;
  end if;

  -- horaires de cette demi-journée
  insert into public.presences (date, saisonnier_id) values (p_date, p_saisonnier)
  on conflict (date, saisonnier_id) do nothing;
  if p_periode = 'matin' then
    update public.presences set matin_debut = d, matin_fin = f, matin_absent = abs
     where date = p_date and saisonnier_id = p_saisonnier
       and (matin_debut, matin_fin, matin_absent) is distinct from (d, f, abs);
  else
    update public.presences set am_debut = d, am_fin = f, am_absent = abs
     where date = p_date and saisonnier_id = p_saisonnier
       and (am_debut, am_fin, am_absent) is distinct from (d, f, abs);
  end if;

  -- ligne d'horaires vide : on la retire
  delete from public.presences
   where date = p_date and saisonnier_id = p_saisonnier
     and matin_debut is null and am_debut is null and not matin_absent and not am_absent;
end $$;

-- Correction et effacement d'une journée par le responsable (tout ou rien)
create or replace function public.corriger_journee(p_date date, p_saisonnier bigint, p_matin jsonb, p_am jsonb)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if coalesce(public.mon_role(), '') <> 'responsable' then
    raise exception 'Réservé au responsable';
  end if;
  perform public.enregistrer_demi_journee(p_date, p_saisonnier, 'matin',
    p_matin ->> 'debut', p_matin ->> 'fin', coalesce((p_matin ->> 'absent')::boolean, false), coalesce(p_matin -> 'quantites', '{}'::jsonb));
  perform public.enregistrer_demi_journee(p_date, p_saisonnier, 'am',
    p_am ->> 'debut', p_am ->> 'fin', coalesce((p_am ->> 'absent')::boolean, false), coalesce(p_am -> 'quantites', '{}'::jsonb));
end $$;

create or replace function public.effacer_journee(p_date date, p_saisonnier bigint)
returns void language plpgsql security invoker set search_path = public as $$
begin
  if coalesce(public.mon_role(), '') <> 'responsable' then
    raise exception 'Réservé au responsable';
  end if;
  delete from public.recoltes  where date = p_date and saisonnier_id = p_saisonnier;
  delete from public.presences where date = p_date and saisonnier_id = p_saisonnier;
end $$;

revoke all on function public.changer_identifiant(uuid, text) from public, anon;
grant execute on function public.changer_identifiant(uuid, text) to authenticated;
revoke all on function public.changer_mot_de_passe(uuid, text) from public, anon;
grant execute on function public.changer_mot_de_passe(uuid, text) to authenticated;
revoke all on function public.enregistrer_demi_journee(date, bigint, text, text, text, boolean, jsonb) from public, anon;
grant execute on function public.enregistrer_demi_journee(date, bigint, text, text, text, boolean, jsonb) to authenticated;
revoke all on function public.corriger_journee(date, bigint, jsonb, jsonb) from public, anon;
grant execute on function public.corriger_journee(date, bigint, jsonb, jsonb) to authenticated;
revoke all on function public.effacer_journee(date, bigint) from public, anon;
grant execute on function public.effacer_journee(date, bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Droits d'accès (Row Level Security)
--    chef        : lit les listes, saisit aujourd'hui et les 7 jours précédents,
--                  ne voit jamais les prix, le SMIC, les montants ni le journal
--    responsable : tout
-- ---------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.invitations, public.profils, public.saisonniers, public.legumes,
  public.recoltes, public.tarifs, public.smic, public.presences to authenticated;
grant select on public.journal_saisies to authenticated;
grant usage, select on all sequences in schema public to authenticated;

alter table public.invitations     enable row level security;
alter table public.profils         enable row level security;
alter table public.saisonniers     enable row level security;
alter table public.legumes         enable row level security;
alter table public.recoltes        enable row level security;
alter table public.tarifs          enable row level security;
alter table public.smic            enable row level security;
alter table public.presences       enable row level security;
alter table public.journal_saisies enable row level security;
drop policy if exists "invitations_responsable" on public.invitations;
create policy "invitations_responsable" on public.invitations for all to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "profils_lecture" on public.profils;
create policy "profils_lecture" on public.profils for select to authenticated
  using (id = auth.uid() or public.mon_role() = 'responsable');
drop policy if exists "profils_modif" on public.profils;
create policy "profils_modif" on public.profils for update to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "saisonniers_lecture" on public.saisonniers;
create policy "saisonniers_lecture" on public.saisonniers for select to authenticated
  using (public.mon_role() is not null);
drop policy if exists "saisonniers_ajout" on public.saisonniers;
create policy "saisonniers_ajout" on public.saisonniers for insert to authenticated
  with check (public.mon_role() = 'responsable');
drop policy if exists "saisonniers_modif" on public.saisonniers;
create policy "saisonniers_modif" on public.saisonniers for update to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "legumes_lecture" on public.legumes;
create policy "legumes_lecture" on public.legumes for select to authenticated
  using (public.mon_role() is not null);
drop policy if exists "legumes_ajout" on public.legumes;
create policy "legumes_ajout" on public.legumes for insert to authenticated
  with check (public.mon_role() = 'responsable');
drop policy if exists "legumes_modif" on public.legumes;
create policy "legumes_modif" on public.legumes for update to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "saisonniers_suppression" on public.saisonniers;
create policy "saisonniers_suppression" on public.saisonniers for delete to authenticated
  using (public.mon_role() = 'responsable');

drop policy if exists "tarifs_responsable" on public.tarifs;
create policy "tarifs_responsable" on public.tarifs for all to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "smic_responsable" on public.smic;
create policy "smic_responsable" on public.smic for all to authenticated
  using (public.mon_role() = 'responsable') with check (public.mon_role() = 'responsable');

drop policy if exists "recoltes_lecture" on public.recoltes;
create policy "recoltes_lecture" on public.recoltes for select to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7));
drop policy if exists "recoltes_ajout" on public.recoltes;
create policy "recoltes_ajout" on public.recoltes for insert to authenticated
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between public.jour_paris() - 7 and public.jour_paris()));
drop policy if exists "recoltes_modif" on public.recoltes;
create policy "recoltes_modif" on public.recoltes for update to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7))
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between public.jour_paris() - 7 and public.jour_paris()));
drop policy if exists "recoltes_suppression" on public.recoltes;
create policy "recoltes_suppression" on public.recoltes for delete to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7));

drop policy if exists "presences_lecture" on public.presences;
create policy "presences_lecture" on public.presences for select to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7));
drop policy if exists "presences_ajout" on public.presences;
create policy "presences_ajout" on public.presences for insert to authenticated
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between public.jour_paris() - 7 and public.jour_paris()));
drop policy if exists "presences_modif" on public.presences;
create policy "presences_modif" on public.presences for update to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7))
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between public.jour_paris() - 7 and public.jour_paris()));
drop policy if exists "presences_suppression" on public.presences;
create policy "presences_suppression" on public.presences for delete to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= public.jour_paris() - 7));

drop policy if exists "journal_lecture" on public.journal_saisies;
create policy "journal_lecture" on public.journal_saisies for select to authenticated
  using (public.mon_role() = 'responsable');

-- ---------------------------------------------------------------------
-- 4. Temps réel (le tableau de bord se met à jour tout seul)
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.recoltes, public.saisonniers, public.legumes,
    public.presences, public.tarifs, public.smic;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 5. Données de départ : les 17 produits et le premier compte responsable
-- ---------------------------------------------------------------------
insert into public.legumes (nom, nom_pt, mode, ordre, bottes_par_colis)
select * from (values
  ('Radis',          'Rabanete',      'colis', 1, 25),
  ('Oignons blancs', 'Cebola branca', 'colis', 2, 15),
  ('Oignons rouges', 'Cebola roxa',   'colis', 3, 15),
  ('Ciboule',        'Cebolinho',     'colis', 4, 12),
  ('Persil',         'Salsa',         'colis', 5, 40),
  ('Persil scotch',  'Salsa scotch',  'unite', 6, 1),
  ('Épluchage',      'Descasque',     'heure', 7, 1),
  ('Plantation',     'Plantação',     'heure', 8, 1),
  ('Binage',         'Sacha',         'heure', 9, 1),
  ('Chou-fleur',     'Couve-flor',    'heure', 10, 1),
  ('Chou vert',      'Couve verde',   'heure', 11, 1),
  ('Chou blanc',     'Couve branca',  'heure', 12, 1),
  ('Chou rouge',     'Couve roxa',    'heure', 13, 1),
  ('Courgette',      'Curgete',       'heure', 14, 1),
  ('Panais',         'Pastinaca',     'heure', 15, 1),
  ('Céleri branche', 'Aipo',          'heure', 16, 1),
  ('Brocoli',        'Brócolos',      'heure', 17, 1)) v(nom, nom_pt, mode, ordre, bottes_par_colis)
where not exists (select 1 from public.legumes);

-- Premier compte responsable : identifiant « admin »
-- (à créer ensuite dans Authentication > Users, voir le guide)
insert into public.invitations (identifiant, nom, role)
values ('admin', 'Responsable', 'responsable')
on conflict (identifiant) do nothing;

commit;
