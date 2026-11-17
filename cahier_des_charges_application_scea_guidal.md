# Cahier des Charges Fonctionnel & Technique
## Application de Suivi des Récoltes - SCEA Guidal

---

## 1. Vue d'ensemble du projet

* **Nom du Projet :** SCEA Guidal - Suivi Récoltes
* **Cible :** Chefs d'équipe / Employés de terrain (saisie) & Responsable / Exploitant (supervision & paie)
* **Objectif Principal :** Digitaliser la collecte quotidienne des quantités récoltées par saisonnier (bottes de radis, colis de choux, etc.) pour simplifier la génération des états de fin de mois destinés aux fiches de paie et à la comptabilité.
* **Plateforme :** Application web/mobile (développée avec Koodcode) responsive et adaptée au terrain.

---

## 2. Identité Visuelle & Charte Graphique

L'application doit refléter le professionnalisme, l'ancrage local et la fraîcheur de la SCEA Guidal à travers les éléments suivants :

### 2.1. Palette de Couleurs
* **Vert Foncé (Primaire) :** `#1E4736` (Utilisé pour les en-têtes, la barre de navigation, les boutons principaux).
* **Rouge Secondaire (Accent) :** `#C61D2D` (Utilisé pour les alertes, les actions de validation importantes, et en clin d'œil au radis).
* **Vert Clair (Validation/Succès) :** `#5OAF54` (Utilisé pour les badges de validation et indicateurs de réussite).
* **Crème / Blanc Cassé (Arrière-plan) :** `#F2EFE6` (Utilisé pour le fond général de l'application afin de donner un aspect chaleureux et naturel, loin du blanc clinique).

### 2.2. Typographie
* **Titres & Éléments de Marque :** *Playfair Display* (Élégant, traditionnel, évoquant le terroir).
* **Corps de Texte & Saisies :** *Montserrat* (Très lisible, moderne, épuré pour une utilisation rapide sur le terrain).

---

## 3. Rôles et Utilisateurs

### 3.1. Rôle 1 : Chef d'équipe / Opérateur Saisie (Terrain)
* **Accès :** Mobile ou tablette simplifiée.
* **Fonctions :**
  * Sélectionner la date du jour (par défaut J).
  * Sélectionner ou rechercher un saisonnier dans la liste.
  * Saisir les quantités récoltées par type de légume (ex: Nombre de bottes de radis, nombre de colis de choux, etc.).
  * Valider et envoyer la saisie journalière.

### 3.2. Rôle 2 : Responsable / Exploitant (Bureau / Supervision)
* **Accès :** Ordinateur ou tablette (Tableau de bord complet).
* **Fonctions :**
  * Visualiser en temps réel les saisies de la journée par équipe/saisonnier.
  * Modifier ou corriger une saisie en cas d'erreur de terrain.
  * Consulter les cumuls par saisonnier sur la semaine ou le mois.
  * **Export Excel mensuel :** Générer un tableau récapitulatif prêt à l'emploi pour le calcul des paies de fin de mois.

---

## 4. Architecture des Données (Modèle prévisionnel)

### 4.1. Table `Saisonniers`
* `id` (Identifiant unique)
* `nom` (Nom de famille)
* `prenom` (Prénom)
* `actif` (Booléen : présent sur l'exploitation ou non)

### 4.2. Table `Legumes` (Évolutive)
* `id`
* `nom` (Ex: Radis - Bottes, Choux - Colis, etc.)
* `unite` (Botte, Colis, Cageot, Kg)

### 4.3. Table `Recoltes` (Journalière)
* `id`
* `date` (AAAA-MM-JJ)
* `saisonnier_id` (Clé étrangère)
* `legume_id` (Clé étrangère)
* `quantite` (Nombre entier ou décimal)
* `saisi_par` (Nom ou ID du chef d'équipe)

---

## 5. Fonctionnalités Clés & Parcours Utilisateur

1. **Connexion & Authentification :** Sélection du profil (Chef d'équipe vs Responsable).
2. **Écran de Saisie Journalière (Chef d'équipe) :**
   * Interface épurée avec les couleurs de la charte.
   * Liste déroulante des saisonniers actifs.
   * Grille de saisie rapide des légumes récoltés dans la journée.
3. **Tableau de Bord & Supervision (Responsable) :**
   * Vue consolidée sous forme de graphiques ou de tableaux clairs.
   * Filtres par période (Jour, Semaine, Mois).
   * Bouton « Exporter vers Excel / CSV ».

---

## 6. Prochaines étapes d'enrichissement

* [ ] Intégrer la liste exhaustive des légumes produits par la SCEA Guidal.
* [ ] Définir les règles de calcul spécifiques pour la paie (le cas échéant).
* [ ] Valider les maquettes d'écrans sous Koodcode.