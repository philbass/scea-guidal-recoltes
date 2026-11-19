-- =====================================================================
--  SCEA Guidal · Mise à jour 07 : journal des modifications des saisies
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run,
--  après maj-06. Peut être relancé sans risque. N'EFFACE RIEN.
--
--  Chaque ajout, modification ou suppression d'une récolte ou d'horaires
--  est noté dans la table journal_saisies : quand, par qui, avant / après.
--  Le responsable le voit dans la fenêtre « Corriger la saisie ».
--  Le chef d'équipe n'y a pas accès (le journal ne contient aucun prix).
--  L'application fonctionne avant et après cette mise à jour.
-- =====================================================================

begin;

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

alter table public.journal_saisies enable row level security;
grant select on public.journal_saisies to authenticated;
drop policy if exists "journal_lecture" on public.journal_saisies;
create policy "journal_lecture" on public.journal_saisies for select to authenticated
  using (public.mon_role() = 'responsable');
-- aucune politique d'ajout, de modification ou de suppression : seul le déclencheur ci-dessous écrit

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

commit;
