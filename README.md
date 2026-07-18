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

### Entraînement — 6 exercices type Aimlabs/Kovaak's
**Gridshot** · **Microshot** · **Flickshot** · **Head Line** · **Strafe Track** · **Reactive Track**
— en 30/60/120 s, records enregistrés par mode et durée.

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
