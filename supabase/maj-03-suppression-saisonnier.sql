-- =====================================================================
--  SCEA Guidal · Mise à jour 03 : supprimer définitivement un saisonnier
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run.
--
--  Permet au responsable (et à lui seul) de supprimer un saisonnier.
--  Ses saisies (récoltes et horaires) sont alors effacées avec lui.
--  Ne supprime rien au moment de l'exécution.
-- =====================================================================

begin;

-- Les saisies d'un saisonnier sont effacées avec lui
alter table public.recoltes drop constraint if exists recoltes_saisonnier_id_fkey;
alter table public.recoltes add constraint recoltes_saisonnier_id_fkey
  foreign key (saisonnier_id) references public.saisonniers (id) on delete cascade;

alter table public.presences drop constraint if exists presences_saisonnier_id_fkey;
alter table public.presences add constraint presences_saisonnier_id_fkey
  foreign key (saisonnier_id) references public.saisonniers (id) on delete cascade;

-- Seul le responsable peut supprimer un saisonnier
drop policy if exists "saisonniers_suppression" on public.saisonniers;
create policy "saisonniers_suppression" on public.saisonniers for delete to authenticated
  using (public.mon_role() = 'responsable');

commit;
