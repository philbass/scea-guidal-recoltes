-- =====================================================================
--  SCEA Guidal · Mise à jour 04 : prix à la botte pour les produits au colis
--  À exécuter UNE SEULE FOIS dans Supabase > SQL Editor > New query > Run.
--
--  Pour un produit au colis, le prix saisi est le prix d'UNE BOTTE.
--  Montant = nombre de colis × bottes par colis × prix de la botte.
--  N'efface rien.
-- =====================================================================

begin;

alter table public.legumes add column if not exists bottes_par_colis integer not null default 1
  check (bottes_par_colis > 0);

update public.legumes set bottes_par_colis = 25 where mode = 'colis' and nom = 'Radis';
update public.legumes set bottes_par_colis = 15 where mode = 'colis' and nom in ('Oignons blancs', 'Oignons rouges');
update public.legumes set bottes_par_colis = 12 where mode = 'colis' and nom = 'Ciboule';
update public.legumes set bottes_par_colis = 40 where mode = 'colis' and nom = 'Persil';

commit;
