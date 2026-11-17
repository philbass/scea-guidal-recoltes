# SCEA Guidal – Suivi Récoltes

Application web et mobile de suivi des récoltes de la SCEA Guidal (Bouafle) : saisie journalière des quantités récoltées par saisonnier, supervision en temps réel et export Excel mensuel pour la paie.

- `app/` : l'application (HTML/JS, sans étape de compilation), publiée avec GitHub Pages
- `supabase/schema.sql` : base de données, droits d'accès et fonctions (Supabase)
- `GUIDE-INSTALLATION.md` : mise en place pas à pas
- `cahier_des_charges_application_scea_guidal.md` : cahier des charges

La clé présente dans `app/config.js` est la clé publique (publishable) de Supabase, prévue pour être exposée : l'accès aux données est contrôlé par les règles de la base (Row Level Security).
