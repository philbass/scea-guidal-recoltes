# Mise en ligne de l'application SCEA Guidal – Suivi Récoltes

Durée : environ 20 minutes. Rien à installer sur l'ordinateur.

Contenu du dossier :

| Fichier | Rôle |
|---|---|
| `app/` | L'application à mettre en ligne (page, logo, réglages) |
| `app/config.js` | Le seul fichier à modifier : adresse et clé Supabase |
| `supabase/schema.sql` | La base de données à créer dans Supabase |

---

## Étape 1 — Créer le projet Supabase

1. Allez sur https://supabase.com et créez un compte gratuit (**Start your project**).
2. Cliquez sur **New project**.
   - Nom : `scea-guidal`
   - Mot de passe de la base : générez-le et **gardez-le en lieu sûr**
   - Région : **Paris (eu-west-3)** ou une région Europe
3. Attendez 1 à 2 minutes que le projet soit prêt.

## Étape 2 — Créer la base de données

1. Dans le menu de gauche : **SQL Editor** → **New query**.
2. Ouvrez le fichier `supabase/schema.sql` avec le Bloc-notes, copiez **tout** le contenu et collez-le.
3. Cliquez sur **Run**. Le message attendu est *Success. No rows returned*.

Cela crée les tables (saisonniers, légumes, récoltes, comptes), les droits d'accès, ainsi que Radis (botte) et Choux (colis).

## Étape 3 — Régler la connexion

Menu **Authentication** → **Sign In / Providers** (ou **Providers** → **Email**) :

- **Enable Email provider** : activé
- **Allow new users to sign up** : activé (sert à la création des comptes depuis l'app ; un compte non invité par le responsable n'a accès à rien)
- **Confirm email** : **désactivé**. Les identifiants ne sont pas de vraies adresses e-mail, aucune confirmation ne peut donc être reçue.

Cliquez sur **Save**.

## Étape 4 — Créer votre compte responsable

1. Menu **Authentication** → **Users** → **Add user** → **Create new user**.
2. E-mail : `admin@scea-guidal.app`
3. Mot de passe : celui de votre choix (6 caractères minimum).
4. Cochez **Auto Confirm User**, puis **Create user**.

Vous vous connecterez avec l'identifiant **admin** et ce mot de passe. Vous pourrez changer le nom affiché dans l'onglet **Équipe** de l'application.

## Étape 5 — Brancher l'application sur Supabase

1. Dans Supabase : **Project Settings** → **API** (ou le bouton **Connect** en haut).
2. Copiez **Project URL** (ex. `https://abcdxyz.supabase.co`) et la clé **anon public** (longue suite de caractères commençant par `eyJ`, ou `sb_publishable_…`).
3. Ouvrez `app/config.js` avec le Bloc-notes et remplacez :
   - `https://VOTRE-PROJET.supabase.co` par la Project URL
   - `VOTRE-CLE-PUBLIQUE-ANON` par la clé anon public
4. Enregistrez.

La clé anon est faite pour être publique : ce sont les droits de la base qui protègent les données. **Ne mettez jamais la clé `service_role`** dans ce fichier.

## Étape 6 — Mettre l'application en ligne (Netlify, gratuit)

1. Allez sur https://app.netlify.com/drop et créez un compte gratuit.
2. Glissez-déposez le **dossier `app`** entier dans la zone de dépôt.
3. Netlify donne une adresse du type `https://nom-au-hasard.netlify.app`. Dans **Site configuration** → **Change site name**, vous pouvez la renommer, par exemple `scea-guidal-recoltes`.

Pour publier une mise à jour plus tard : **Deploys** → glissez de nouveau le dossier `app`.

## Étape 7 — Premier essai

1. Ouvrez l'adresse Netlify et connectez-vous avec **admin**.
2. Onglet **Saisonniers et légumes** : ajoutez vos saisonniers.
3. Onglet **Équipe** : créez un compte pour chaque chef d'équipe (nom, identifiant, mot de passe, rôle « Chef d'équipe »).
4. Testez avec un compte chef sur un téléphone : il ne doit voir que l'écran de saisie.

## Installer l'app sur le téléphone

- **Android (Chrome)** : ouvrir l'adresse → menu ⋮ → **Ajouter à l'écran d'accueil**.
- **iPhone (Safari)** : ouvrir l'adresse → bouton Partager → **Sur l'écran d'accueil**.

L'app s'ouvre alors en plein écran avec l'icône du radis, et la personne reste connectée.

---

## Qui peut faire quoi

| | Chef d'équipe | Responsable |
|---|---|---|
| Saisir les récoltes | Oui, pour les 7 derniers jours | Oui, sans limite de date |
| Voir le tableau de bord et exporter | Non | Oui |
| Corriger ou supprimer une saisie | Non (il peut refaire la saisie du jour) | Oui |
| Gérer saisonniers et légumes | Non | Oui |
| Créer des comptes, changer les mots de passe | Non | Oui |

Ces règles sont appliquées par la base de données elle-même, pas seulement par l'affichage.

## En cas de problème

| Message | Solution |
|---|---|
| « Configuration à terminer » | `config.js` n'est pas rempli (étape 5) |
| « Compte pas encore confirmé » | Désactiver **Confirm email** (étape 3) |
| « Compte non activé » | Le compte a été désactivé dans **Équipe**, ou il a été créé dans Supabase sans invitation. Recréez-le depuis l'onglet Équipe. |
| « Identifiant ou mot de passe incorrect » | Le responsable peut changer le mot de passe dans **Équipe** → **Mot de passe** |
| Les nouvelles saisies n'apparaissent pas toutes seules | Supabase → **Database** → **Publications** → `supabase_realtime` : vérifier que `recoltes` est coché |

**Projet gratuit Supabase** : il se met en pause après 7 jours sans aucune utilisation. Pendant la saison, l'usage quotidien l'évite. Après une longue pause, il suffit de le relancer depuis le tableau de bord Supabase (**Restore project**).
