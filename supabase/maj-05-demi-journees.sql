-- =====================================================================
--  SCEA Guidal · Mise à jour 05 : saisie par demi-journée et absences
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run,
--  AVANT de publier la version de l'application qui va avec.
--
--  - Chaque récolte est rattachée au matin ou à l'après-midi.
--    Les récoltes déjà saisies sont classées « matin ».
--  - Un saisonnier peut être noté absent le matin et/ou l'après-midi.
--  N'efface rien. L'application actuelle continue de fonctionner.
-- =====================================================================

begin;

-- 1. Récoltes : matin ou après-midi
alter table public.recoltes add column if not exists periode text not null default 'matin'
  check (periode in ('matin', 'am'));
alter table public.recoltes drop constraint if exists recoltes_date_saisonnier_id_legume_id_key;
alter table public.recoltes drop constraint if exists recoltes_jour_periode_unique;
alter table public.recoltes add constraint recoltes_jour_periode_unique
  unique (date, saisonnier_id, legume_id, periode);

-- 2. Horaires : absences du matin et de l'après-midi
alter table public.presences add column if not exists matin_absent boolean not null default false;
alter table public.presences add column if not exists am_absent    boolean not null default false;

-- 3. L'ancienne fonction de saisie reste utilisable (elle écrit dans « matin »)
create or replace function public.enregistrer_saisie(p_date date, p_saisonnier bigint, p_quantites jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare
  k text;
  v numeric;
begin
  for k, v in select key, value::numeric from jsonb_each_text(p_quantites) loop
    if v > 0 then
      insert into public.recoltes (date, saisonnier_id, legume_id, quantite, periode)
      values (p_date, p_saisonnier, k::bigint, v, 'matin')
      on conflict (date, saisonnier_id, legume_id, periode)
      do update set quantite = excluded.quantite
      where public.recoltes.quantite is distinct from excluded.quantite;
    else
      delete from public.recoltes
      where date = p_date and saisonnier_id = p_saisonnier and legume_id = k::bigint and periode = 'matin';
    end if;
  end loop;
end $$;

-- 4. Enregistrer une demi-journée : horaires (ou absence) + quantités
create or replace function public.enregistrer_demi_journee(
  p_date date, p_saisonnier bigint, p_periode text,
  p_debut text, p_fin text, p_absent boolean, p_quantites jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare
  d   time := nullif(p_debut, '')::time;
  f   time := nullif(p_fin, '')::time;
  abs boolean := coalesce(p_absent, false);
  k   text;
  v   numeric;
begin
  if p_periode not in ('matin', 'am') then
    raise exception 'Période invalide';
  end if;
  if abs then d := null; f := null; end if;

  -- quantités de cette demi-journée
  for k, v in select key, value::numeric from jsonb_each_text(coalesce(p_quantites, '{}'::jsonb)) loop
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

commit;
