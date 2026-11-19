-- =====================================================================
--  SCEA Guidal · Mise à jour 06 : sécurité des comptes, contrôles de saisie,
--  heure de Paris, bottes par colis datées
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run.
--  Peut être relancé sans risque. N'EFFACE AUCUNE SAISIE.
--
--  1. Création de compte : un compte ne peut être créé que s'il a été invité
--     depuis l'onglet Équipe il y a moins de 15 minutes, avec un identifiant
--     en @scea-guidal.app. Toute autre inscription est refusée.
--     Les invitations restées en attente sont supprimées.
--  2. Dates : « aujourd'hui » est calculé à l'heure de Paris (et non en heure
--     universelle) pour la période de saisie du chef d'équipe.
--  3. La base vérifie elle-même chaque saisie : pas de date future, pas de
--     quantité négative, horaires obligatoires dès qu'il y a des quantités,
--     fin après début, heures « à l'heure » pas plus longues que la présence.
--  4. Correction et effacement d'une journée en une seule opération
--     (tout ou rien) : fonctions corriger_journee et effacer_journee.
--  5. Le nombre de bottes par colis est daté avec le prix (table tarifs) :
--     le changer ne modifie plus la paie des mois passés.
--  6. Retire deux anciennes fonctions de saisie qui ne servent plus.
--
--  L'application publiée fonctionne avant et après cette mise à jour.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. « Aujourd'hui » à l'heure de Paris
-- ---------------------------------------------------------------------
create or replace function public.jour_paris()
returns date language sql stable set search_path = public as $$
  select (now() at time zone 'Europe/Paris')::date
$$;

-- Période du chef d'équipe : aujourd'hui et les 7 jours précédents (heure de Paris)
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

-- ---------------------------------------------------------------------
-- 2. Création de compte réservée aux invitations récentes
-- ---------------------------------------------------------------------
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

-- Invitations restées en attente : supprimées (sauf « admin » tant qu'aucun responsable n'existe)
delete from public.invitations
 where created_at < now() - interval '15 minutes'
   and exists (select 1 from public.profils where role = 'responsable');

-- ---------------------------------------------------------------------
-- 3. Bottes par colis datées avec le prix
-- ---------------------------------------------------------------------
alter table public.tarifs add column if not exists bottes_par_colis integer check (bottes_par_colis > 0);
update public.tarifs t
   set bottes_par_colis = case when l.mode = 'colis' then coalesce(l.bottes_par_colis, 1) else 1 end
  from public.legumes l
 where l.id = t.legume_id and t.bottes_par_colis is null;

-- ---------------------------------------------------------------------
-- 4. Saisie d'une demi-journée, avec les contrôles faits par la base
-- ---------------------------------------------------------------------
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

revoke all on function public.enregistrer_demi_journee(date, bigint, text, text, text, boolean, jsonb) from public, anon;
grant execute on function public.enregistrer_demi_journee(date, bigint, text, text, text, boolean, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Correction et effacement d'une journée (responsable), tout ou rien
--    p_matin / p_am : {"debut": "07:00", "fin": "12:00", "absent": false, "quantites": {"1": 10}}
-- ---------------------------------------------------------------------
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

revoke all on function public.corriger_journee(date, bigint, jsonb, jsonb) from public, anon;
grant execute on function public.corriger_journee(date, bigint, jsonb, jsonb) to authenticated;
revoke all on function public.effacer_journee(date, bigint) from public, anon;
grant execute on function public.effacer_journee(date, bigint) to authenticated;

-- ---------------------------------------------------------------------
-- 6. Anciennes fonctions de saisie, remplacées par enregistrer_demi_journee
-- ---------------------------------------------------------------------
drop function if exists public.enregistrer_journee(date, bigint, jsonb, jsonb);
drop function if exists public.enregistrer_saisie(date, bigint, jsonb);

commit;
