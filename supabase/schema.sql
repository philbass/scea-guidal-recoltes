-- =====================================================================
--  SCEA Guidal · Suivi des récoltes — schéma de la base Supabase
--  À coller en une seule fois dans Supabase > SQL Editor > New query > Run
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

-- Comptes prévus par le responsable, en attente de création
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

create table if not exists public.legumes (
  id     bigint generated always as identity primary key,
  nom    text not null,
  unite  text not null check (unite in ('Botte', 'Colis', 'Cageot', 'Kg')),
  actif  boolean not null default true,
  ordre  integer not null default 0
);

-- Une ligne = une quantité d'un légume récoltée par un saisonnier un jour donné
create table if not exists public.recoltes (
  id            bigint generated always as identity primary key,
  date          date not null,
  saisonnier_id bigint not null references public.saisonniers (id),
  legume_id     bigint not null references public.legumes (id),
  quantite      numeric(10, 2) not null check (quantite >= 0),
  saisi_par     uuid references public.profils (id),
  corrige_par   uuid references public.profils (id),
  modifie_le    timestamptz not null default now(),
  unique (date, saisonnier_id, legume_id)
);
create index if not exists recoltes_date_idx on public.recoltes (date);

-- ---------------------------------------------------------------------
-- 2. Fonctions utilitaires
-- ---------------------------------------------------------------------

-- Rôle de la personne connectée ('chef', 'responsable' ou null si compte inactif / inconnu)
create or replace function public.mon_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profils where id = auth.uid() and actif
$$;

-- Crée le profil quand un compte invité est créé
create or replace function public.creer_profil()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  inv   public.invitations;
  ident text := lower(split_part(new.email, '@', 1));
begin
  select * into inv from public.invitations where identifiant = ident;
  if found then
    insert into public.profils (id, identifiant, nom, role)
    values (new.id, ident, inv.nom, inv.role)
    on conflict (id) do nothing;
    delete from public.invitations where identifiant = ident;
  end if;
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

-- Enregistre la saisie d'un saisonnier pour une journée (quantité 0 = supprimée)
create or replace function public.enregistrer_saisie(p_date date, p_saisonnier bigint, p_quantites jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare
  k text;
  v numeric;
begin
  for k, v in select key, value::numeric from jsonb_each_text(p_quantites) loop
    if v > 0 then
      insert into public.recoltes (date, saisonnier_id, legume_id, quantite)
      values (p_date, p_saisonnier, k::bigint, v)
      on conflict (date, saisonnier_id, legume_id)
      do update set quantite = excluded.quantite
      where public.recoltes.quantite is distinct from excluded.quantite;
    else
      delete from public.recoltes
      where date = p_date and saisonnier_id = p_saisonnier and legume_id = k::bigint;
    end if;
  end loop;
end $$;

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

revoke all on function public.changer_mot_de_passe(uuid, text) from public, anon;
grant execute on function public.changer_mot_de_passe(uuid, text) to authenticated;
revoke all on function public.enregistrer_saisie(date, bigint, jsonb) from public, anon;
grant execute on function public.enregistrer_saisie(date, bigint, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Droits d'accès (Row Level Security)
--    chef        : lit les listes, saisit les 7 derniers jours, ne voit rien d'autre
--    responsable : tout
-- ---------------------------------------------------------------------

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

alter table public.invitations enable row level security;
alter table public.profils     enable row level security;
alter table public.saisonniers enable row level security;
alter table public.legumes     enable row level security;
alter table public.recoltes    enable row level security;

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

drop policy if exists "recoltes_lecture" on public.recoltes;
create policy "recoltes_lecture" on public.recoltes for select to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7));
drop policy if exists "recoltes_ajout" on public.recoltes;
create policy "recoltes_ajout" on public.recoltes for insert to authenticated
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between current_date - 7 and current_date));
drop policy if exists "recoltes_modif" on public.recoltes;
create policy "recoltes_modif" on public.recoltes for update to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7))
  with check (public.mon_role() = 'responsable'
              or (public.mon_role() = 'chef' and date between current_date - 7 and current_date));
drop policy if exists "recoltes_suppression" on public.recoltes;
create policy "recoltes_suppression" on public.recoltes for delete to authenticated
  using (public.mon_role() = 'responsable'
         or (public.mon_role() = 'chef' and date >= current_date - 7));

-- ---------------------------------------------------------------------
-- 4. Temps réel (le tableau de bord se met à jour tout seul)
-- ---------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.recoltes, public.saisonniers, public.legumes;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------
-- 5. Données de départ
-- ---------------------------------------------------------------------
insert into public.legumes (nom, unite, ordre)
select * from (values ('Radis', 'Botte', 1), ('Choux', 'Colis', 2)) v(nom, unite, ordre)
where not exists (select 1 from public.legumes);

-- Premier compte responsable : identifiant « admin »
-- (à créer ensuite dans Authentication > Users, voir le guide)
insert into public.invitations (identifiant, nom, role)
values ('admin', 'Responsable', 'responsable')
on conflict (identifiant) do nothing;
