# ◈ SENS LAB

Aim trainer & calibrateur de sensibilité pour FPS compétitifs — **Valorant, CS2, Overwatch 2, Apex Legends, COD/Warzone**.

![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf) ![Windows](https://img.shields.io/badge/Windows-x64-0078d6)

## 🎯 Télécharger et jouer

**[→ Télécharger SensLab.exe (dernière release)](../../releases/latest)**

Un seul fichier, rien à installer : télécharge, double-clique, joue.

> Windows SmartScreen peut afficher un avertissement au premier lancement (exe non signé) :
> clique **« Informations complémentaires » → « Exécuter quand même »**.

## Fonctionnalités

### Sens Finder — trouve ta sensibilité idéale
Calibration **à l'aveugle** : chaque round modifie ta sensibilité sans te le dire, le moteur mesure ta
performance et en déduit ta sens optimale.

- 3 protocoles : **Rapide** (~3,5 min), **Standard** (~6 min, rounds adaptatifs), **Précision** (~9 min)
- Score par round basé sur le **débit de Fitts** (bits/s, ISO 9241-9) : normalise la distance et la taille
  des cibles pour comparer équitablement les rounds
- Détection **overshoot/undershoot** sur le mouvement balistique de chaque flick
- Ajustement de courbe pondéré + rounds de confirmation + **plage recommandée** (l'optimum est une plage,
  pas un point — cf. recherche NVIDIA sur la sensibilité en visée FPS)
- Verdict avec équivalents de sens pour les 5 jeux, eDPI et cm/360

### Entraînement — 25 exercices en 5 packs, type Aimlabs/Kovaak's
Difficulté ◆ à ◆◆◆◆◆ · 30/60/120 s · records enregistrés par mode et durée.

| Pack | Exercices |
|---|---|
| **VITESSE** | Gridshot · Spider · Gridshot Ultra · Hypergrid |
| **PRÉCISION** | Microshot · Head Line · Longshot · Head Micro · Microdot |
| **FLICK** | Flickshot · Wide Flick · Sixshot · Head Flick · Multiflick |
| **TRACKING** | Strafe Track · Micro Track · Reactive Track · Vertical Track · Air Track · Turbo Track |
| **RÉFLEXES** | Reflex Click · Dodge Shot · Head Rush · Reflex Micro · Dodge Micro |

Les modes RÉFLEXES ajoutent des cibles **éphémères** (raté si tu ne cliques pas à temps)
et des cibles **mobiles** qui strafent.

### Dashboard de fin d'entraînement
- **Replay première personne** : la caméra rejoue exactement tes mouvements, les cibles
  réapparaissent aux mêmes instants (re-simulation fidèle image par image). Traînée du viseur
  colorée : vert = sur la cible, orange = dépassement, ✕ orange = clic trop tôt, ✕ rouge = raté.
  Lecture/pause, vitesse ×0,5/×1/×2, navigation à la souris dans la timeline.
- **Stats détaillées** : record, précédent meilleur, précision, coups/tirs, cibles tuées, série max.
- **Analyse poussée** : décomposition du kill médian (réaction → flick → ajustement),
  overshoot/undershoot, clics trop tôt, biais directionnel gauche/droite, endurance
  (1re vs 2e moitié) ; en tracking : retard/avance moyen derrière la cible, temps de
  re-synchronisation après les inversions.
- **Classement du mode joué** + liste déroulante pour enchaîner un autre exercice.

### Classement en ligne
Choisis un pseudo dans RÉGLAGES : tes scores d'entraînement sont envoyés automatiquement et
comparés à ceux des autres joueurs dans l'onglet **CLASSEMENT** (top 20 par exercice et durée,
meilleur score par joueur).

### Précision
- **Raw input Windows natif** (WM_INPUT) : l'accélération du pointeur est ignorée, comme en jeu
- Sens **exactement angulaire** : `degrés/count = yaw du jeu × sens × DPI` — la même formule que le jeu
- FOV par jeu (échelle 4:3 d'Apex convertie correctement), V-Sync off, jusqu'à 400 FPS

## Compiler depuis les sources

1. Télécharger [Godot 4.7](https://godotengine.org/download/windows/)
2. `godot --path . ` pour lancer, ou importer le projet dans l'éditeur
3. Export : préconfiguré dans `export_presets.cfg` (Windows Desktop, pck embarqué)

## Structure

| Fichier | Rôle |
|---|---|
| `main.gd` | Jeu : monde 3D, menu, sens finder, modes d'entraînement |
| `analysis.gd` | Stats : débit de Fitts, ajustement parabolique pondéré, leave-one-out |
| `gamedb.gd` | Base des jeux : yaw, FOV, conversions de sens |
| `uikit.gd` | Widgets UI |
