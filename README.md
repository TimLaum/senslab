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
- Score par round = **throughput effectif ISO 9241-9** (MacKenzie) : IDe = log₂(Ae/We + 1) avec
  **We = 4,133 × σ des points d'impact** (ratés inclus) — normalise le compromis vitesse/précision
  propre au joueur, pas seulement la difficulté des cibles
- **Échauffement exclu** : les premiers 20 % de chaque round (adaptation à la nouvelle sens) ne comptent
  pas, et l'effet d'**apprentissage** entre rounds est retiré (détrend ridge co-ajusté)
- Courbe ajustée par **processus gaussien** (noyau RBF sur ln k, moyenne a priori parabolique,
  bruit pondéré par le nombre de cibles) ; rounds adaptatifs placés par **optimisation bayésienne (UCB)**
- Recommandation = **médiane des optima bootstrap** (bagging, 140 rééchantillonnages) ;
  plage = plateau du GP ∩ intervalle bootstrap 5–95 % — l'optimum est un **plateau**, pas un point
  (cf. NVIDIA Research, arXiv:2203.12050 & IEEE CoG 2023 : optimum large de ~4×)
- Détection **overshoot/undershoot** sur le mouvement balistique de chaque flick
- Verdict avec équivalents de sens pour les 5 jeux, eDPI et cm/360 ; pipeline validé par
  simulation Monte-Carlo (`test_math.gd` : erreur médiane à la borne de Cramér-Rao)

### Entraînement — 26 exercices en 5 packs, type Aimlabs/Kovaak's
Difficulté ◆ à ◆◆◆◆◆ · 30/60/120 s · records enregistrés par mode et durée.

Chaque exercice est **paramétrable avant lancement** : taille des cibles, écart max entre
cibles, nombre de cibles simultanées, durée de vie, vitesse de déplacement (tracking : taille,
vitesse, largeur de zone, amplitude verticale). Paramètres par défaut = score classé ;
paramètres modifiés = run libre (ni record ni classement), mémorisés par exercice.

Les **Gridshot** placent leurs cibles sur une vraie **grille N×N** (3×3, 5×5) ancrée devant
toi : par défaut les cibles sont serrées, et le réglage « écart des cibles » écarte la grille
pour monter en difficulté.

| Pack | Exercices |
|---|---|
| **VITESSE** | Gridshot (3×3) · Spider · Gridshot 5×5 · Hypergrid (5×5) |
| **PRÉCISION** | Microshot · Head Line · Longshot · Head Micro · Microdot |
| **FLICK** | Flickshot · Wide Flick · Sixshot · Head Flick · Multiflick |
| **TRACKING** | Strafe Track · Micro Track · Reactive Track · Vertical Track · Air Track · Turbo Track |
| **RÉFLEXES** | Reflex Click · Dodge Shot · Head Rush · Reflex Micro · Dodge Micro · Sonar |

Les modes RÉFLEXES ajoutent des cibles **éphémères** (raté si tu ne cliques pas à temps)
et des cibles **mobiles** qui strafent. **Sonar** fait apparaître la cible **hors de l'écran**
(n'importe où autour de toi) : un **ping 3D** t'indique sa direction, tourne-toi et flicke.

### Playlists — tes propres routines
Onglet **PLAYLISTS** : sélectionne des exercices, règle leurs paramètres si tu veux
(ou laisse-les par défaut), nomme la playlist et enregistre-la. Crée-en autant que tu veux.
À la lecture, les exercices s'enchaînent **dans un ordre aléatoire** ; entre chacun, le dashboard
de fin affiche la progression (« exercice 2/5 ») et un bouton **EXERCICE SUIVANT ▶**.
Durée réglable par playlist. Un exercice laissé aux paramètres par défaut reste **classé**
(record + classement en ligne) ; personnalisé, il est **libre**.

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

### Défi multijoueur 1v1vX
Crée une **room** (code court à partager, jusqu'à 16 joueurs, pas de minimum), monte une
playlist d'exercices — ouverte à tous ou réservée à l'hôte — et lance : chaque round démarre
**en simultané chez tout le monde** (heure serveur). Le meilleur score du round marque 1 point ;
tableau des points et vainqueur dans la room.

### Classement en ligne + replays du top 5
Choisis un pseudo dans RÉGLAGES : tes scores d'entraînement sont envoyés automatiquement et
comparés à ceux des autres joueurs dans l'onglet **CLASSEMENT** (top 20 par exercice et durée,
meilleur score par joueur). À chaque record perso, ton replay part aussi en ligne : un bouton
**▶ VOIR** à côté des 5 meilleurs de chaque classement rejoue leur partie en vue première
personne — pour voir exactement comment le top joue.

Onglet **CLASSEMENT → GÉNÉRAL** : un classement global sur **100**. Pour chaque catégorie,
on prend les **3 exercices les plus joués** ; ton score y est ramené sur 100 (par rapport au
meilleur mondial), moyenné par catégorie, puis sur les 5 catégories (durée de référence 60 s).
Récompense la polyvalence — une catégorie non jouée compte 0.

### Précision & confort
- **Raw input Windows natif** (WM_INPUT) : l'accélération du pointeur est ignorée, comme en jeu
- Sens **exactement angulaire** : `degrés/count = yaw du jeu × sens × DPI` — la même formule que le jeu
- FOV par jeu (échelle 4:3 d'Apex convertie correctement), V-Sync off
- Réglages : **plein écran ou fenêtré** (1440p/1080p/900p/720p), **choix de l'écran**,
  **FPS max** (144 → illimité), **FPS réduits quand le jeu n'a pas le focus**,
  **2 touches de tir assignables** (clavier ou souris, clic gauche par défaut),
  **volume**, **V-Sync**, **MSAA**, **échelle de rendu 3D** (petites configs)
- **Viseur type Valorant** : color picker, point central et lignes activables séparément,
  longueur / épaisseur / écart au centre réglables au pixel, contour, **flash au tir réussi**
  activable, **aperçu live**
- **Couleurs de la map** : color pickers pour les **carrés** et les **lignes** de la grille,
  et pour le **ciel/fond** ; **animation de disparition des cibles** et **glow des sphères**
  activables (disparition nette par défaut, glow activé par défaut)
- **Son de tir personnalisable** : importe ton propre fichier `.mp3` / `.ogg` / `.wav` dans les réglages

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
