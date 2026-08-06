# Yacolis - Journal de Bord du Projet

Ce document sert de mémoire à long terme pour le développement du projet Yacolis. Il doit être lu par l'agent IA à chaque nouvelle session et mis à jour après chaque avancée significative.

## État Actuel

### Architecture Initiale
- Création de l'architecture de base inspirée de `mobile1/agir_transfert`.
- Dossiers de base créés : `core`, `core/theme`, `core/services`, `config`, `repositories`, `shared`, `data`.
- Ajout des dossiers de la couche présentation (vides pour l'instant) : `presentation/screens`, `presentation/widgets`, `presentation/navigation`, `presentation/layouts`, `presentation/dialogs`.
- Fichiers de configuration de base copiés : `main.dart`, `routes.dart`, `app_theme.dart` et `app_colors.dart`.
- Développement du `HomeDrawer` et de la grille d'actions sur l'écran d'accueil.
- Développement poussé de `DeliveryScreen` (Design map, sheet responsive, barres d'actions, ajustement des couleurs).
- Création de `AddressSelectionScreen` pour la recherche d'adresse, connecté aux champs de `DeliveryScreen`.
- Intégration du GPS réel avec `geolocator` et `geocoding` pour récupérer la position de l'utilisateur et l'afficher dans les champs d'adresse.
- Création d'un Modal Bottom Sheet détaillé sur `HomeScreen` pour les options de localisation (Capture 2).
