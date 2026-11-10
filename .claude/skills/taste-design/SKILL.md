---
name: taste-design
description: Applique des règles de design sobres, ergonomiques et responsives pour créer ou modifier des interfaces, pages web et dashboards qui n'ont pas l'air générés par une IA.
---

# Design d'interface sobre et ergonomique

## Priorités, dans l'ordre
1. Sécurité et clarté de l'information
2. Rapidité d'exécution de la tâche
3. Accessibilité
4. Esthétique

## Avant de coder
- Identifier l'utilisateur, sa tâche principale et son contexte d'usage.
- Réutiliser les composants et les tokens existants du projet.
- Donner une seule action principale à chaque écran.

## Identité visuelle
- Définir les couleurs, espacements, rayons et typographies dans des tokens.
- Utiliser des fonds neutres et une seule couleur d'accent.
- Réserver le rouge, l'orange et le jaune aux urgences et aux états métier.
- Ne jamais transmettre une information par la couleur seule : ajouter un libellé ou une icône.
- Séparer les zones par l'espacement, puis par des bordures de 1 px si nécessaire.
- Réserver les ombres discrètes aux éléments flottants (menus, modales).

## À éviter
- Dégradés décoratifs, effets de verre et textes en dégradé
- Grilles de cartes identiques et cartes imbriquées
- Icônes décoratives et émojis utilisés comme interface
- Grandes sections héroïques dans une application métier
- Textes vagues, faux chiffres et données inventées
- Animations décoratives

## Mise en page
- Utiliser une grille régulière et une échelle d'espacement de 4 ou 8 px.
- Placer les informations et actions les plus importantes en premier.
- Adapter la densité : tableaux compacts pour le travail répété, plus d'espace pour la lecture.
- Aligner les nombres à droite avec `tabular-nums`.

## Typographie
- Utiliser une à deux familles de police et une hiérarchie limitée.
- Garder le texte courant à 16 px, ou 14 px minimum dans les tableaux denses.
- Limiter les paragraphes à environ 75 caractères par ligne.
- Vérifier les textes en français et en malagasy, qui peuvent être plus longs.

## Ergonomie et états
- Prévoir les états : chargement, vide, erreur, succès, désactivé et hors ligne.
- Afficher les erreurs près du champ, avec la solution.
- Demander confirmation avant toute action irréversible.
- Préserver les filtres, la pagination et les saisies lors de la navigation.
- Afficher les dates, heures et unités sans ambiguïté.

## Responsive
- Concevoir d'abord pour mobile, puis vérifier à 360, 768, 1024 et 1440 px.
- Éviter tout défilement horizontal de la page.
- Prévoir une alternative lisible aux tableaux larges sur mobile.
- Garder des zones tactiles d'au moins 44 × 44 px.

## Animations
- Limiter les animations à celles qui expliquent un changement d'état.
- Durée : 120 à 200 ms.
- Courbe : `cubic-bezier(0.4, 0, 0.2, 1)`.
- Animer seulement `transform` et `opacity` lorsque c'est possible.
- Respecter `prefers-reduced-motion`.

## Accessibilité
- Viser le niveau WCAG 2.2 AA.
- Rendre toutes les actions utilisables au clavier, avec un focus visible.
- Utiliser du HTML sémantique et des libellés de formulaire explicites.

## Vérification finale
- [ ] La tâche principale est compréhensible en moins de 5 secondes.
- [ ] Tous les états sont gérés.
- [ ] Aucun texte ni valeur de style n'est codé en dur.
- [ ] L'interface fonctionne à toutes les largeurs prévues.
- [ ] Le clavier et les contrastes sont vérifiés.
- [ ] Rien de décoratif ne peut être retiré sans perte d'information.