# Mise en ligne de l'application SCEA Guidal – Suivi Récoltes

Durée : environ 20 minutes. Rien à installer sur l'ordinateur.

Contenu du dossier :

| Fichier | Rôle |
|---|---|
| `app/` | L'application publiée sur GitHub Pages (page, logo, réglages) |
| `.github/workflows/pages.yml` | La publication automatique sur GitHub Pages |
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

Cela crée les tables (saisonniers, produits, récoltes, comptes) et les droits d'accès.

4. Faites de même avec `supabase/maj-01-identifiant.sql`, `supabase/maj-02-paie.sql`, `supabase/maj-03-suppression-saisonnier.sql`, `supabase/maj-04-bottes-par-colis.sql`, puis `supabase/maj-05-demi-journees.sql`. Ce dernier ajoute les horaires, les modes de paie, les tarifs, le SMIC, ainsi que les 17 produits.

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

Vous vous connecterez avec l'identifiant **admin** et ce mot de passe. Vous pourrez ensuite changer votre nom affiché et votre identifiant dans l'onglet **Équipe** de l'application.

## Étape 5 — Brancher l'application sur Supabase

1. Dans Supabase : **Project Settings** → **API** (ou le bouton **Connect** en haut).
2. Copiez **Project URL** (ex. `https://abcdxyz.supabase.co`) et la clé **anon public** (longue suite de caractères commençant par `eyJ`, ou `sb_publishable_…`).
3. Ouvrez `app/config.js` avec le Bloc-notes et remplacez :
   - `https://VOTRE-PROJET.supabase.co` par la Project URL
   - `VOTRE-CLE-PUBLIQUE-ANON` par la clé anon public
4. Enregistrez.

La clé anon est faite pour être publique : ce sont les droits de la base qui protègent les données. **Ne mettez jamais la clé `service_role`** dans ce fichier.

## Étape 6 — Mettre l'application en ligne (GitHub Pages, gratuit)

L'application est publiée depuis le dépôt GitHub **philbass/scea-guidal-recoltes** :

- Adresse de l'app : **https://philbass.github.io/scea-guidal-recoltes/**
- Code source : https://github.com/philbass/scea-guidal-recoltes

La publication est automatique : à chaque envoi sur la branche `main`, le fichier `.github/workflows/pages.yml` republie le dossier `app/` en une à deux minutes. Pour suivre une publication : onglet **Actions** du dépôt (coche verte = en ligne).

**Pour publier une modification** (depuis le dossier du projet, dans un terminal) :

```bash
git add -A
git commit -m "Description de la modification"
git push
```

Sans terminal, on peut aussi modifier un fichier directement sur github.com (icône crayon → **Commit changes**) : l'app se republie de la même façon.

**Pour réinstaller sur un autre compte GitHub** : créer un dépôt public, y envoyer le dossier du projet, puis **Settings** → **Pages** → **Source : GitHub Actions**. L'adresse devient `https://<compte>.github.io/<nom-du-dépôt>/`.

## Étape 7 — Premier essai

1. Ouvrez https://philbass.github.io/scea-guidal-recoltes/ et connectez-vous avec **admin**.
2. Onglet **Équipe** → **Modifier** sur votre compte : changez votre nom affiché et, si vous le souhaitez, votre identifiant de connexion (à la place de « admin »).
3. Onglet **Saisonniers** : ajoutez vos saisonniers. Onglet **Produits et tarifs** : saisissez le prix de chaque produit et le SMIC horaire.
4. Onglet **Équipe** : créez un compte pour chaque chef d'équipe (nom, identifiant, mot de passe, rôle « Chef d'équipe »).
5. Testez avec un compte chef sur un téléphone : il ne doit voir que l'écran de saisie.

## Mises à jour de la base de données

Certaines évolutions de l'app demandent d'ajouter une fonction dans Supabase. Le fichier correspondant se trouve dans `supabase/` et commence par `maj-`. À faire **une seule fois** par fichier : **SQL Editor** → **New query** → coller le contenu → **Run**.

| Fichier | Apporte | À exécuter si |
|---|---|---|
| `maj-01-identifiant.sql` | Changer l'identifiant de connexion d'un compte | Toujours, après `schema.sql` |
| `maj-02-paie.sql` | Horaires matin et après-midi, paie au colis, à l'unité ou à l'heure, tarifs datés, SMIC, noms en portugais | Toujours, après `maj-01`. **Attention : efface les anciens produits et toutes les saisies de récolte déjà faites.** À exécuter juste avant de publier la version qui va avec. |

| `maj-03-suppression-saisonnier.sql` | Supprimer définitivement un saisonnier, avec toutes ses saisies | Toujours, après `maj-02`. N'efface rien au moment de l'exécution. |

| `maj-04-bottes-par-colis.sql` | Prix à la botte pour les produits au colis (Radis 25, Oignons 15, Ciboule 12, Persil 40 bottes par colis) | Toujours, après `maj-03`. N'efface rien. |

| `maj-05-demi-journees.sql` | Saisie séparée du matin et de l'après-midi, absences par demi-journée (les récoltes déjà saisies sont classées « matin ») | Toujours, après `maj-04`, **avant** de publier la version qui va avec. N'efface rien. |

Exécutez les fichiers dans l'ordre de leur numéro.

## Tester en local (mode démo)

Pour essayer une nouvelle version sur l'ordinateur avant de la publier, sans toucher à la vraie base :

1. Dans le dossier `outils`, clic droit sur `serveur-local.ps1` → **Exécuter avec PowerShell**. Laissez la fenêtre ouverte.
2. Ouvrez **http://localhost:8080/?demo** dans le navigateur.
3. Choisissez « responsable » ou « chef d'équipe ». Les données sont fictives et restent dans ce navigateur. Le bouton **Réinitialiser la démo** les remet à zéro.

Sans `?demo` dans l'adresse, la version locale se connecte à la vraie base.

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
| Gérer saisonniers et produits | Non | Oui |
| Voir les prix, le SMIC et les montants | Non | Oui |
| Créer des comptes, changer les mots de passe | Non | Oui |

Ces règles sont appliquées par la base de données elle-même, pas seulement par l'affichage.

## En cas de problème

| Message | Solution |
|---|---|
| « Configuration à terminer » | `config.js` n'est pas rempli (étape 5) |
| « Compte pas encore confirmé » | Désactiver **Confirm email** (étape 3) |
| « Compte non activé » | Le compte a été désactivé dans **Équipe**, ou il a été créé dans Supabase sans invitation. Recréez-le depuis l'onglet Équipe. |
| « Identifiant ou mot de passe incorrect » | Le responsable peut changer le mot de passe dans **Équipe** → **Mot de passe** |
| « La base doit être mise à jour » | Exécuter le fichier `supabase/maj-…sql` indiqué (voir « Mises à jour de la base de données ») |
| L'app affiche encore l'ancienne version | Attendre la fin de la publication (onglet **Actions** sur GitHub), puis recharger la page |
| Les nouvelles saisies n'apparaissent pas toutes seules | Supabase → **Database** → **Publications** → `supabase_realtime` : vérifier que `recoltes` est coché |

**Projet gratuit Supabase** : il se met en pause après 7 jours sans aucune utilisation. Pendant la saison, l'usage quotidien l'évite. Après une longue pause, il suffit de le relancer depuis le tableau de bord Supabase (**Restore project**).
