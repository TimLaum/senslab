extends Node3D
# ============================================================
#  SENS LAB — trainer d'aim + calibrateur de sensibilité
#  Valorant · CS2 · Overwatch 2 · Apex · COD
#  Sens angulaire exacte : degrés/count = yaw_jeu × sens × k
# ============================================================

const HEYE := 1.6
const R_DIST := 10.0
const TP_REF := 2.4          # bits/s (ID nominal / durée de phase, fallback)
const TP_REF_E := 5.5        # bits/s (throughput EFFECTIF ISO 9241-9, par cible)
const WARMUP_FRAC := 0.2     # début de round exclu des stats (adaptation à la sens)

enum Mode { MENU, COUNT, F_FLICK, F_TRACK, TRAIN, F_RESULTS, T_RESULTS, SANDBOX, R_VIEW }

const PROTOCOLS := {
	"rapide": {
		"label": "RAPIDE", "time": "~3,5 min",
		"desc": "5 sens testées + 1 confirmation",
		"base": [1.0, 0.72, 0.85, 1.18, 1.32],
		"flick": 20.0, "track": 10.0, "refine": 0, "confirm": 1,
	},
	"standard": {
		"label": "STANDARD", "time": "~6 min",
		"desc": "5 sens + 2 rounds adaptatifs + 1 confirmation",
		"base": [1.0, 0.72, 0.85, 1.18, 1.32],
		"flick": 25.0, "track": 12.0, "refine": 2, "confirm": 1,
	},
	"precision": {
		"label": "PRÉCISION", "time": "~9 min",
		"desc": "7 sens + 2 adaptatifs + 2 confirmations",
		"base": [1.0, 0.66, 0.80, 0.93, 1.09, 1.25, 1.42],
		"flick": 25.0, "track": 14.0, "refine": 2, "confirm": 2,
	},
}

const PACKS := [
	{"key": "vitesse", "label": "VITESSE", "desc": "cadence brute · cibles généreuses"},
	{"key": "precision", "label": "PRÉCISION", "desc": "petites cibles · contrôle du micro-ajustement"},
	{"key": "flick", "label": "FLICK", "desc": "grands angles · un seul coup"},
	{"key": "tracking", "label": "TRACKING", "desc": "suivi continu · lecture de trajectoire"},
	{"key": "reflex", "label": "RÉFLEXES", "desc": "cibles éphémères ou mobiles · réaction pure"},
]

# click : simul cibles, rayon r (m), cône yaw, plage pitch, anchored (zone fixe)
#         + ttl (s, la cible expire = raté) + move (°/s, la cible strafe)
# track : paramètres du traqueur dans "trk" (kind smooth/react/orbit/vert)
const MODES := {
	# ---- VITESSE ----
	"grid": {"name": "GRIDSHOT", "desc": "grille 3×3 · 3 cibles actives · cibles proches, vitesse brute", "icon": "grid",
		"pack": "vitesse", "diff": 1, "type": "click",
		"simul": 3, "r": 0.45, "cone": 26.0, "p_lo": -2.0, "p_hi": 16.0, "anchored": true,
		"grid_n": 3, "grid_step": 6.0},
	"spider": {"name": "SPIDER", "desc": "une grosse cible à la fois · enchaîne sans t'arrêter", "icon": "spider",
		"pack": "vitesse", "diff": 2, "type": "click",
		"simul": 1, "r": 0.42, "cone": 22.0, "p_lo": -2.0, "p_hi": 14.0, "anchored": true},
	"grid5": {"name": "GRIDSHOT 5×5", "desc": "grille 5×5 · 5 cibles actives · plus petites", "icon": "grid",
		"pack": "vitesse", "diff": 3, "type": "click",
		"simul": 5, "r": 0.36, "cone": 32.0, "p_lo": -3.0, "p_hi": 17.0, "anchored": true,
		"grid_n": 5, "grid_step": 5.5},
	"hyper": {"name": "HYPERGRID", "desc": "grille 5×5 large · 4 petites cibles · grands écarts", "icon": "grid",
		"pack": "vitesse", "diff": 5, "type": "click",
		"simul": 4, "r": 0.28, "cone": 36.0, "p_lo": -5.0, "p_hi": 19.0, "anchored": true,
		"grid_n": 5, "grid_step": 7.5},
	# ---- PRÉCISION ----
	"micro": {"name": "MICROSHOT", "desc": "micro-corrections · petites cibles proches", "icon": "micro",
		"pack": "precision", "diff": 2, "type": "click",
		"simul": 1, "r": 0.16, "cone": 10.0, "p_lo": -4.0, "p_hi": 8.0, "anchored": false},
	"head": {"name": "HEAD LINE", "desc": "headshots · cibles têtes sur une ligne", "icon": "head",
		"pack": "precision", "diff": 2, "type": "click",
		"simul": 1, "r": 0.18, "cone": 30.0, "p_lo": 1.0, "p_hi": 2.2, "anchored": false},
	"long": {"name": "LONGSHOT", "desc": "cibles lointaines · flicks calmes et propres", "icon": "dot",
		"pack": "precision", "diff": 3, "type": "click",
		"simul": 1, "r": 0.14, "cone": 40.0, "p_lo": 0.0, "p_hi": 10.0, "anchored": false},
	"headmicro": {"name": "HEAD MICRO", "desc": "têtes minuscules · crosshair placement pur", "icon": "head",
		"pack": "precision", "diff": 4, "type": "click",
		"simul": 1, "r": 0.12, "cone": 32.0, "p_lo": 1.2, "p_hi": 2.0, "anchored": false},
	"dot": {"name": "MICRODOT", "desc": "points minuscules · zéro marge d'erreur", "icon": "dot",
		"pack": "precision", "diff": 5, "type": "click",
		"simul": 1, "r": 0.09, "cone": 9.0, "p_lo": -3.0, "p_hi": 6.0, "anchored": false},
	# ---- FLICK ----
	"flick": {"name": "FLICKSHOT", "desc": "flicks longs · distance variable", "icon": "flick",
		"pack": "flick", "diff": 2, "type": "click",
		"simul": 1, "r": 0.30, "cone": 35.0, "p_lo": -4.0, "p_hi": 18.0, "anchored": false},
	"wide": {"name": "WIDE FLICK", "desc": "flicks très larges · presque un 180", "icon": "flick",
		"pack": "flick", "diff": 3, "type": "click",
		"simul": 1, "r": 0.28, "cone": 55.0, "p_lo": -6.0, "p_hi": 20.0, "anchored": false},
	"six": {"name": "SIXSHOT", "desc": "2 cibles ancrées aux extrêmes · va-et-vient", "icon": "six",
		"pack": "flick", "diff": 4, "type": "click",
		"simul": 2, "r": 0.26, "cone": 50.0, "p_lo": -4.0, "p_hi": 18.0, "anchored": true},
	"headflick": {"name": "HEAD FLICK", "desc": "flicks sur têtes · hauteur constante", "icon": "head",
		"pack": "flick", "diff": 4, "type": "click",
		"simul": 1, "r": 0.16, "cone": 45.0, "p_lo": 1.0, "p_hi": 2.4, "anchored": false},
	"multi": {"name": "MULTIFLICK", "desc": "3 petites cibles éparpillées très loin", "icon": "six",
		"pack": "flick", "diff": 5, "type": "click",
		"simul": 3, "r": 0.22, "cone": 48.0, "p_lo": -4.0, "p_hi": 18.0, "anchored": true},
	# ---- TRACKING ----
	"strafe": {"name": "STRAFE TRACK", "desc": "tracking lisse · strafes amples", "icon": "strafe",
		"pack": "tracking", "diff": 2, "type": "track",
		"trk": {"kind": "smooth", "r": 0.33, "v": 24.0, "band": 26.0, "pitch_amp": 3.5}},
	"microtrk": {"name": "MICRO TRACK", "desc": "petite cible lente · contrôle fin", "icon": "micro",
		"pack": "tracking", "diff": 3, "type": "track",
		"trk": {"kind": "smooth", "r": 0.20, "v": 13.0, "band": 11.0, "pitch_amp": 2.0}},
	"react": {"name": "REACTIVE TRACK", "desc": "tracking réactif · inversions brutales", "icon": "react",
		"pack": "tracking", "diff": 3, "type": "track",
		"trk": {"kind": "react", "r": 0.33, "v": 46.0, "band": 20.0, "pitch_amp": 1.5,
			"flip_lo": 0.25, "flip_hi": 0.7}},
	"vert": {"name": "VERTICAL TRACK", "desc": "montées et descentes · contrôle du poignet", "icon": "vert",
		"pack": "tracking", "diff": 4, "type": "track",
		"trk": {"kind": "vert", "r": 0.30, "v": 26.0, "band": 6.0, "pitch_amp": 8.0}},
	"air": {"name": "AIR TRACK", "desc": "orbites amples · cible aérienne", "icon": "orbit",
		"pack": "tracking", "diff": 4, "type": "track",
		"trk": {"kind": "orbit", "r": 0.33, "spd": 1.7, "band": 15.0, "pitch_amp": 7.0}},
	"turbo": {"name": "TURBO TRACK", "desc": "inversions ultra rapides · réactivité max", "icon": "react",
		"pack": "tracking", "diff": 5, "type": "track",
		"trk": {"kind": "react", "r": 0.30, "v": 72.0, "band": 18.0, "pitch_amp": 1.2,
			"flip_lo": 0.18, "flip_hi": 0.45}},
	# ---- RÉFLEXES ----
	"reflex": {"name": "REFLEX CLICK", "desc": "1,1 s pour toucher la cible · sinon perdue", "icon": "reflex",
		"pack": "reflex", "diff": 2, "type": "click",
		"simul": 1, "r": 0.35, "cone": 30.0, "p_lo": -3.0, "p_hi": 14.0, "anchored": false, "ttl": 1.1},
	"dodge": {"name": "DODGE SHOT", "desc": "cibles qui strafent · anticipe le mouvement", "icon": "strafe",
		"pack": "reflex", "diff": 3, "type": "click",
		"simul": 1, "r": 0.32, "cone": 28.0, "p_lo": -2.0, "p_hi": 12.0, "anchored": false, "move": 22.0},
	"headrush": {"name": "HEAD RUSH", "desc": "têtes mobiles sur une ligne · headshots only", "icon": "head",
		"pack": "reflex", "diff": 4, "type": "click",
		"simul": 1, "r": 0.17, "cone": 30.0, "p_lo": 1.0, "p_hi": 2.2, "anchored": false, "move": 18.0},
	"reflexmicro": {"name": "REFLEX MICRO", "desc": "petite cible · 0,9 s chrono", "icon": "reflex",
		"pack": "reflex", "diff": 4, "type": "click",
		"simul": 1, "r": 0.18, "cone": 24.0, "p_lo": -3.0, "p_hi": 8.0, "anchored": false, "ttl": 0.9},
	"dodgemicro": {"name": "DODGE MICRO", "desc": "petites cibles mobiles et éphémères · l'enfer", "icon": "strafe",
		"pack": "reflex", "diff": 5, "type": "click",
		"simul": 1, "r": 0.20, "cone": 30.0, "p_lo": -2.0, "p_hi": 10.0, "anchored": false,
		"move": 30.0, "ttl": 2.2},
	"sonar": {"name": "SONAR", "desc": "la cible apparaît hors de l'écran · repère-la au son 3D puis flicke", "icon": "reflex",
		"pack": "reflex", "diff": 4, "type": "click",
		"simul": 1, "r": 0.34, "cone": 0.0, "p_lo": -16.0, "p_hi": 14.0, "anchored": false, "locate": true},
}
const MODE_ORDER := [
	"grid", "spider", "grid5", "hyper",
	"micro", "head", "long", "headmicro", "dot",
	"flick", "wide", "six", "headflick", "multi",
	"strafe", "microtrk", "react", "vert", "air", "turbo",
	"reflex", "dodge", "headrush", "reflexmicro", "dodgemicro", "sonar",
]
const DURATIONS := [30, 60, 120]

# journal des versions (le plus récent en premier) — affiché dans l'onglet PATCH NOTES
const CHANGELOG := [
	{"v": "1.17", "notes": [
		"SONAR : le signal 3D est joué une fois à l'apparition, plus distinct et bien mieux spatialisé (gauche/droite)",
		"SONAR : la cible reste toujours à une hauteur visible (ni sous le sol ni trop haut)",
		"Classements : précision et série max enregistrées et affichées à côté du score",
	]},
	{"v": "1.16", "notes": [
		"Classement général : note /100 par joueur (3 exercices les plus joués par catégorie, ramenés sur 100, moyennés par catégorie puis sur les 5)",
		"Mode SONAR : la cible apparaît hors de l'écran, un ping 3D indique sa direction",
		"Glow des sphères activable/désactivable dans les réglages",
	]},
	{"v": "1.15", "notes": [
		"Couleur des carrés et des lignes de la grille du sol/murs personnalisables",
		"Changement de couleur du viseur au tir réussi (flash) activable/désactivable",
	]},
	{"v": "1.14", "notes": [
		"Bouton RECOMMENCER dans le menu pause : relance le run en cours sans repasser par le menu",
	]},
	{"v": "1.13", "notes": [
		"Viseur type Valorant : point/lignes/contour séparés, longueur/épaisseur/écart au pixel, aperçu live",
		"Color pickers pour la couleur du viseur et du ciel/fond",
		"Son de tir personnalisable (.mp3, .ogg, .wav)",
		"Animation de disparition des cibles activable (disparition nette par défaut)",
		"Confirmation avant de quitter avec ÉCHAP dans le menu",
		"Sens finder : ÉCHAP pendant le décompte met en pause au lieu de perdre la run",
	]},
	{"v": "1.12", "notes": [
		"Gridshot en vraie grille N×N (3×3, 5×5) ; l'écart des cibles règle la difficulté",
	]},
	{"v": "1.11", "notes": [
		"Playlists solo : routines nommées d'exercices, jouées dans un ordre aléatoire",
	]},
	{"v": "1.10", "notes": [
		"Bouton de vérification des mises à jour + re-vérification automatique toutes les 30 min",
	]},
	{"v": "1.9", "notes": [
		"Sens finder : les cibles restent toujours dans le champ de vision",
	]},
	{"v": "1.8", "notes": [
		"Exercices paramétrables avant lancement",
		"Replays des 5 meilleurs scores de chaque classement",
	]},
	{"v": "1.7", "notes": [
		"Réglages fenêtre / écran / FPS, touches de tir assignables, viseur personnalisable",
	]},
	{"v": "1.6", "notes": [
		"Sens Finder : moteur mathématique de calibration de niveau recherche",
	]},
	{"v": "1.5", "notes": [
		"Défi multijoueur 1v1vX (rooms, playlist partagée, scores en simultané)",
	]},
	{"v": "1.4", "notes": [
		"25 exercices d'entraînement + dashboard de fin avec replay et analyse",
	]},
	{"v": "1.3", "notes": [
		"Ajustements et corrections",
	]},
	{"v": "1.2", "notes": [
		"Mise à jour automatique intégrée (bouton d'installation)",
	]},
	{"v": "1.1", "notes": [
		"Classement en ligne des scores",
	]},
	{"v": "1.0", "notes": [
		"Version initiale : aim trainer + sens finder",
	]},
]

# ---------- état global ----------
var mode: int = Mode.MENU
var paused := false
var game := "valorant"
var sens := 0.4
var dpi := 800.0
var fov_val := 103.0
var k := 1.0

# caméra
var cam: Camera3D
var yaw := 0.0
var pitch := 0.0

# cibles
var targets: Array = []          # {node, ang:Vector2, r_ang, born, d0}
var freeze_until := 0
var path := {}
var has_path := false
var anchor_yaw := 0.0
var grid_last := -1               # dernière cellule de grille touchée (à éviter au respawn)

# tracking
var trk_active := false
var trk_p := {}                  # paramètres du traqueur (kind, r, v, band…)
var trk_anchor_yaw := 0.0
var trk_yaw := 0.0
var trk_v := 24.0
var trk_pitch_base := 6.0
var trk_pitch := 6.0
var trk_pv := 20.0
var trk_ph := 0.0
var trk_flip_in := 0.5
var trk_on := false

# sens finder
var protocol := "standard"
var plan: Array = []             # {k, stage}
var round_i := 0
var rounds: Array = []
var cur := {}
var phase_timer := 0.0
var count_timer := 0.0
var count_ctx := "finder"
var k_final := 1.0
var k_lo := 1.0
var k_hi := 1.0
var fit := {"a": 0.0, "b": 0.0, "c": 0.0, "r2": 0.0}
var fres_scan := {}            # balayage GP (courbe + plateau) pour l'affichage
var confidence_txt := ""

# entraînement
var t_mode := "grid"
var t_dur := 60
var t_score := 0
var t_combo := 0
var t_best_streak := 0
var t_cfg := {}                  # config effective du run : MODES[t_mode] + overrides custom
var t_ranked := true             # false si paramètres personnalisés → ni record ni classement
var custom := {}                 # overrides (clé param → valeur) appliqués au prochain run

# replay : tout est enregistré pendant un entraînement pour le dashboard
var rec_samples: Array = []      # Vector3(t, yaw, pitch) ~200 Hz
var rec_tgt: Array = []          # Vector3(t, yaw, pitch) de la cible (tracking)
var rec_on: Array = []           # bool par échantillon tracking : sur la cible ?
var rec_targets: Array = []      # {t0, ang0, t1, ang1, r_ang, fate}
var rec_clicks: Array = []       # {t, ang, hit, early}
var rec_last_t := -1.0

# classement en ligne
var lb: Leaderboard
var pseudo := ""
var lb_mode := "grid"
var lb_dur := 60

# défi multijoueur (rooms 1v1vX, 16 max)
const ROOM_MAX := 16
var room: Room
var room_code := ""
var room_is_host := false
var room_data := {}
var room_srv_offset := 0.0     # epoch serveur − horloge locale
var room_launched := -1        # dernier round lancé localement
var room_played := -1          # round auquel appartient le run en cours
var room_active := false
var room_poll: Timer
var duel_setup: VBoxContainer
var duel_lobby: VBoxContainer
var duel_join_in: LineEdit
var duel_status: Label
var duel_code_lbl: Label
var duel_players_grid: GridContainer
var duel_modes_list: VBoxContainer
var duel_add_opt: OptionButton
var duel_add_row: HBoxContainer
var duel_host_btn: Button
var duel_finish_btn: Button
var duel_count_lbl: Label
var duel_dur := 30
var duel_dur_btns: Array = []
var duel_open := true
var duel_open_btn: Button

# mise à jour auto
var upd: Updater
var upd_btn: Button
var upd_check_btn: Button
var upd_manual := false          # le check en cours vient du bouton (→ feedback)

# affichage / performances / touches de tir
const WIN_MODES := [
	{"label": "PLEIN ÉCRAN", "fs": true},
	{"label": "FENÊTRÉ 2560×1440", "w": 2560, "h": 1440},
	{"label": "FENÊTRÉ 1920×1080", "w": 1920, "h": 1080},
	{"label": "FENÊTRÉ 1600×900", "w": 1600, "h": 900},
	{"label": "FENÊTRÉ 1280×720", "w": 1280, "h": 720},
]
const FPS_CAPS := [144, 240, 360, 400, 500, 0]     # 0 = illimité
const FPS_BG := [15, 30, 60, 0]                    # 0 = comme actif
var fps_cap := 400
var fps_bg := 30
var fire_binds: Array = ["mouse:1", ""]            # 2 touches de tir assignables
var fire_wait := -1                                # slot en attente de capture
var fire_btns: Array = []
var disp_size_opt: OptionButton
var disp_screen_opt: OptionButton
var disp_fps_opt: OptionButton
var disp_fpsbg_opt: OptionButton
const RSCALES := [1.0, 0.83, 0.67, 0.5]
var vol_slider: HSlider
var vsync_opt: OptionButton
var msaa_opt: OptionButton
var rscale_opt: OptionButton
var ch_col_pick: ColorPickerButton
var ch_preview: CrossDraw          # aperçu live du viseur dans les réglages
var bg_col_pick: ColorPickerButton      # couleur du ciel/fond derrière la grille
var grid_base_pick: ColorPickerButton   # couleur des carrés du sol/murs
var grid_line_pick: ColorPickerButton   # couleur des lignes de la grille
var grid_mats: Array = []               # matériaux de grille à recolorer
var pop_opt: OptionButton               # animation de disparition des cibles
var pop_enabled := false
var glow_opt: OptionButton              # effet de glow (bloom) sur les sphères
var custom_snd_lbl: Label               # état du son de tir personnalisé
var world_env: Environment
var snd_hit_default: AudioStream        # bip par défaut, pour réinitialiser
var quit_panel: Control                 # confirmation avant de quitter

# ---------- UI ----------
var ui: CanvasLayer
var crosshair: CrossDraw
var hud_root: Control
var hud_l1: Label
var hud_l2: Label
var hud_l3: Label
var hud_raw: Label
var hud_timer: Label
var hud_hint: Label
var menu_panel: Control
var count_panel: Control
var cnt_round_lbl: Label
var cnt_num_lbl: Label
var cnt_score_lbl: Label
var pause_panel: Control
var pause_restart_btn: Button
var fres_panel: Control
var tres_panel: Control
var in_sens: LineEdit
var in_dpi: LineEdit
var in_fov: LineEdit
var fov_hint_lbl: Label
var derived_lbl: Label
var last_calib_lbl: Label
var sum_lbl: Label
var dur_btns: Array = []
var nav_btns := {}
var tab_panels := {}
var mode_rec_lbls := {}
var game_btns := {}
var in_pseudo: LineEdit
var lb_grid: GridContainer
var lb_status: Label
var lb_mode_opt: OptionButton
var lb_dur_btns: Array = []
var lb_general := false             # onglet CLASSEMENT : vue générale vs par exercice
var lb_ex_box: VBoxContainer        # sélecteurs exercice/durée (masqués en général)
var lb_view_btns: Array = []
const LB_GEN_DUR := 60              # durée de référence du classement général
var tres_net: Label
var res_game_lbl: Label
var res_sens_lbl: Label
var res_range_lbl: Label
var res_conf_lbl: Label
var res_equiv_box: VBoxContainer
var res_diag: RichTextLabel
var res_table: GridContainer
var curve_ctl: Control
var tres_title: Label
var tres_score: Label
var tres_record: Label
var rp_overlay: ReplayOverlay
var rp_time_ctl: TimelineDraw
var rp_play_btn: Button
var rp_speed_btns: Array = []
var dash_chips_box: GridContainer
var dash_diag: RichTextLabel
var dash_lb_grid: GridContainer
var dash_lb_status: Label
var dash_mode_opt: OptionButton

# panneau de pré-lancement (paramétrage du mode)
var setup_panel: Control
var setup_title: Label
var setup_desc: Label
var setup_rows: VBoxContainer
var setup_status: Label
var setup_dur_btns: Array = []
var setup_sliders: Array = []    # [{spec, slider, lbl}]
var setup_mode := "grid"
var setup_from_dash := false

# visionneuse des replays du classement (top 5)
var rvw_panel: Control
var rvw_title: Label
var rvw_overlay: ReplayOverlay
var rvw_time_ctl: TimelineDraw
var rvw_play_btn: Button
var rvw_speed_btns: Array = []
var rvw_backup := {}             # replay perso sauvegardé pendant la visionneuse

# ---- playlists solo (routines nommées, exercices en ordre aléatoire) ----
var playlists: Array = []        # [{name, dur, items:[{mk, cust}]}]
var pl_list_box: VBoxContainer
var pl_edit_panel: Control
var pl_edit_title: Label
var pl_name_in: LineEdit
var pl_items_box: VBoxContainer
var pl_add_opt: OptionButton
var pl_dur_btns: Array = []
var pl_edit_idx := -1            # index en cours d'édition (-1 = nouvelle)
var pl_edit_name := ""
var pl_edit_dur := 60
var pl_edit_items: Array = []    # copie de travail : [{mk, cust}]
# lecture en cours
var pl_active := false
var pl_queue: Array = []         # items mélangés
var pl_i := 0
var pl_play_name := ""
var pl_play_dur := 60
# le panneau de paramétrage sert aussi à capturer les params d'un item de playlist
var setup_ctx := "play"          # "play" = lance le run · "playlist" = enregistre dans l'item
var setup_item_idx := -1
var setup_launch_btn: Button
var setup_dur_row: HBoxContainer
# barre playlist du dashboard de fin de run
var tres_pl_row: HBoxContainer
var tres_pl_lbl: Label
var tres_pl_next: Button

# lecture du replay première personne
var rp_t := 0.0
var rp_dur := 60.0
var rp_playing := true
var rp_speed := 1.0
var rp_cls := PackedInt32Array()   # classe par échantillon : 0 trajet, 1 sur cible, 2 défaut
var rp_nodes := {}                 # index de rec_targets -> MeshInstance3D fantôme
var rp_trk_node: MeshInstance3D
var dash_worst_off := 0.0

var snd_hit: AudioStreamPlayer
var snd_miss: AudioStreamPlayer
var snd_round: AudioStreamPlayer
var locate_snd: AudioStreamPlayer3D     # ping 3D en boucle pour le mode SONAR

# ============================================================
func _ready() -> void:
	randomize()
	Engine.max_fps = 400
	Input.use_accumulated_input = false
	lb = Leaderboard.new()
	add_child(lb)
	lb.top_received.connect(_on_lb_top)
	lb.submitted.connect(_on_lb_submitted)
	lb.replay_received.connect(_on_lb_replay)
	lb.all_received.connect(_on_lb_all)
	room = Room.new()
	add_child(room)
	room.state_received.connect(_on_room_state)
	room.now_received.connect(func(epoch: float):
		room_srv_offset = epoch - Time.get_unix_time_from_system())
	room.op_done.connect(_on_room_op)
	room_poll = Timer.new()
	room_poll.wait_time = 1.5
	room_poll.timeout.connect(func():
		if room_code != "":
			room.fetch(room_code))
	add_child(room_poll)
	upd = Updater.new()
	add_child(upd)
	upd.update_available.connect(_on_update_available)
	upd.checked.connect(_on_upd_checked)
	upd.progress.connect(_on_update_progress)
	upd.failed.connect(_on_update_failed)
	# re-vérification automatique toutes les 30 min : le bouton ⬆ apparaît
	# en cours de session, sans redémarrer le jeu
	var upd_timer := Timer.new()
	upd_timer.wait_time = 1800.0
	upd_timer.autostart = true
	upd_timer.timeout.connect(func(): upd.check())
	add_child(upd_timer)
	_build_world()
	_build_sounds()
	_build_ui()
	get_viewport().size_changed.connect(_apply_camera_fov)
	_load_prefs()
	_goto_menu()
	upd.check()

# ============================================================
#  MONDE 3D
# ============================================================
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0B0F17")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("28303F")
	env.ambient_light_energy = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color("0B0F17")
	env.fog_density = 0.012
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world_env = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.5
	add_child(sun)

	add_child(_grid_plane(Vector2(44, 44), Vector3(0, 0, 0), Vector3.ZERO, 22.0))
	add_child(_grid_plane(Vector2(44, 36), Vector3(0, 18, -22), Vector3(90, 0, 0), 22.0))
	add_child(_grid_plane(Vector2(44, 36), Vector3(0, 18, 22), Vector3(-90, 0, 0), 22.0))
	add_child(_grid_plane(Vector2(36, 44), Vector3(-22, 18, 0), Vector3(0, 0, -90), 22.0))
	add_child(_grid_plane(Vector2(36, 44), Vector3(22, 18, 0), Vector3(0, 0, 90), 22.0))

	cam = Camera3D.new()
	cam.position = Vector3(0, HEYE, 0)
	cam.current = true
	add_child(cam)
	# auditeur audio solidaire de la caméra → spatialisation gauche/droite du SONAR
	var listener := AudioListener3D.new()
	cam.add_child(listener)
	listener.make_current()
	_apply_camera_fov()

func _apply_camera_fov() -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := 16.0 / 9.0
	if vp.y > 0:
		aspect = vp.x / vp.y
	cam.fov = clamp(GameDB.vfov(game, fov_val, aspect), 30.0, 120.0)

func _grid_plane(size: Vector2, pos: Vector3, rot: Vector3, tiles: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float tiles = 22.0;
uniform vec3 grid_base = vec3(0.045, 0.058, 0.082);
uniform vec3 grid_line = vec3(0.10, 0.28, 0.36);
void fragment() {
	vec2 uv = UV * tiles;
	vec2 g = abs(fract(uv) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.06, min(g.x, g.y));
	ALBEDO = mix(grid_base, grid_line, line * 0.4);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tiles", tiles)
	mi.material_override = mat
	grid_mats.append(mat)
	mi.position = pos
	mi.rotation_degrees = rot
	return mi

# ============================================================
#  SONS
# ============================================================
func _build_sounds() -> void:
	snd_hit = _beep_player(880.0, 0.07, 0.35, 1320.0)
	snd_hit_default = snd_hit.stream
	snd_miss = _beep_player(190.0, 0.05, 0.30, 0.0)
	snd_round = _beep_player(520.0, 0.16, 0.30, 780.0)
	# SONAR : un signal 3D joué UNE fois à l'apparition de la cible. Panoramique
	# fort (panning_strength) + auditeur sur la caméra pour bien localiser à l'oreille.
	locate_snd = AudioStreamPlayer3D.new()
	locate_snd.stream = _sonar_cue()
	locate_snd.unit_size = 14.0
	locate_snd.max_distance = 120.0
	locate_snd.volume_db = 6.0
	locate_snd.panning_strength = 3.0
	add_child(locate_snd)

# signal SONAR joué une fois : balayage descendant + brin de bruit (plus facile à
# localiser qu'une tonalité pure) ; volontairement différent du son de tir
func _sonar_cue() -> AudioStreamWAV:
	var rate := 44100
	var dur := 0.5
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var prog := t / dur
		var f := lerpf(780.0, 420.0, prog)          # balayage descendant
		var env := sin(PI * prog)                    # attaque/chute douces
		var s := sin(TAU * f * t) * 0.8
		s += (randf() * 2.0 - 1.0) * 0.14            # bruit = repères de localisation
		data.encode_s16(i * 2, int(clamp(s * env, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

func _beep_player(freq: float, dur: float, vol: float, freq2: float) -> AudioStreamPlayer:
	var rate := 44100
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-7.0 * float(i) / n)
		var s := sin(TAU * freq * t)
		if freq2 > 0.0:
			s = s * 0.6 + sin(TAU * freq2 * t) * 0.4
		data.encode_s16(i * 2, int(clamp(s * env * vol, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	var p := AudioStreamPlayer.new()
	p.stream = w
	add_child(p)
	return p

# ============================================================
#  UI — construction
# ============================================================
func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	crosshair = CrossDraw.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(crosshair)
	_build_hud()
	_build_menu()
	_build_count()
	_build_pause()
	_build_fres()
	_build_tres()
	_build_setup()
	_build_rvw()
	_build_pl_editor()
	_build_quit()

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_root)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 22; top.offset_right = -22; top.offset_top = 14
	top.add_theme_constant_override("separation", 26)
	hud_root.add_child(top)
	hud_l1 = UIKit.label("", 13, UIKit.COL_TEXT, true)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_raw = UIKit.label("raw input ✓", 13, UIKit.COL_OK, true)
	hud_timer = UIKit.label("", 15, UIKit.COL_TEXT, true)
	for n in [UIKit.label("◈ SENS LAB", 13, UIKit.COL_MUTED, true), hud_l1, sp, hud_raw, hud_timer]:
		top.add_child(n)

	var bot := HBoxContainer.new()
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_left = 22; bot.offset_right = -22; bot.offset_top = -44; bot.offset_bottom = -14
	bot.add_theme_constant_override("separation", 26)
	hud_root.add_child(bot)
	hud_l2 = UIKit.label("", 13, UIKit.COL_MUTED, true)
	hud_l3 = UIKit.label("", 13, UIKit.COL_MUTED, true)
	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud_hint = UIKit.label("", 13, UIKit.COL_MUTED, true)
	for n in [hud_l2, hud_l3, sp2, hud_hint]:
		bot.add_child(n)
	hud_root.visible = false

func _build_menu() -> void:
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.032, 0.052, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(dim)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for mrg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(mrg, 48)
	menu_panel.add_child(mc)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 30)
	mc.add_child(root)

	# ---- barre du haut ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	var logo := UIKit.label("◈ SENS LAB", 26, UIKit.COL_TEXT, true)
	var tag := UIKit.label("AIM TRAINER · SENS FINDER", 11, UIKit.COL_MUTED, true)
	tag.size_flags_vertical = Control.SIZE_SHRINK_END
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum_lbl = UIKit.label("", 13, UIKit.COL_ACCENT2, true)
	sum_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	for n in [logo, tag, sp, sum_lbl]:
		top.add_child(n)
	root.add_child(top)

	# ---- corps : sidebar + contenu ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(240, 0)
	side.add_theme_constant_override("separation", 6)
	body.add_child(side)
	for entry in [["train", "ENTRAÎNEMENT"], ["playlists", "PLAYLISTS"], ["duel", "DÉFI 1V1VX"], ["finder", "SENS FINDER"], ["board", "CLASSEMENT"], ["patch", "PATCH NOTES"], ["settings", "RÉGLAGES"]]:
		var nb := _nav_btn(entry[1])
		nb.pressed.connect(_show_tab.bind(entry[0]))
		nav_btns[entry[0]] = nb
		side.add_child(nb)
	var spv := Control.new()
	spv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spv)
	upd_btn = UIKit.btn("", true, 13)
	upd_btn.visible = false
	upd_btn.pressed.connect(_on_update_clicked)
	side.add_child(upd_btn)
	upd_check_btn = UIKit.btn("VÉRIFIER LES MISES À JOUR", false, 11)
	upd_check_btn.pressed.connect(_on_check_updates)
	side.add_child(upd_check_btn)
	last_calib_lbl = UIKit.label("", 11, UIKit.COL_MUTED, true)
	last_calib_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(last_calib_lbl)
	side.add_child(HSeparator.new())
	var quit := _nav_btn("QUITTER")
	quit.pressed.connect(func(): get_tree().quit())
	side.add_child(quit)
	side.add_child(UIKit.label("v" + Updater.VERSION, 11, UIKit.COL_MUTED, true))

	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)

	tab_panels["train"] = _build_tab_train()
	tab_panels["playlists"] = _build_tab_playlists()
	tab_panels["duel"] = _build_tab_duel()
	tab_panels["finder"] = _build_tab_finder()
	tab_panels["board"] = _build_tab_board()
	tab_panels["patch"] = _build_tab_patch()
	tab_panels["settings"] = _build_tab_settings()
	for tp in tab_panels.values():
		tp.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_child(tp)
	_show_tab("train")

func _nav_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", UIKit.mono())
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE
	var off := StyleBoxFlat.new()
	off.bg_color = Color(0, 0, 0, 0)
	off.set_content_margin_all(13)
	off.content_margin_left = 18
	var hov := UIKit.btn_style(UIKit.COL_PANEL2, UIKit.COL_LINE)
	hov.content_margin_left = 18
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_color_override("font_color", UIKit.COL_MUTED)
	b.add_theme_color_override("font_hover_color", UIKit.COL_TEXT)
	b.add_theme_color_override("font_pressed_color", UIKit.COL_TEXT)
	return b

func _set_nav_active(b: Button, on: bool) -> void:
	if on:
		var sb := UIKit.btn_style(UIKit.COL_PANEL2, UIKit.COL_PANEL2)
		sb.border_color = UIKit.COL_ACCENT
		sb.set_border_width_all(0)
		sb.border_width_left = 3
		sb.content_margin_left = 18
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", UIKit.COL_TEXT)
	else:
		var off := StyleBoxFlat.new()
		off.bg_color = Color(0, 0, 0, 0)
		off.set_content_margin_all(13)
		off.content_margin_left = 18
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_color_override("font_color", UIKit.COL_MUTED)

func _show_tab(tab: String) -> void:
	for tk in tab_panels:
		tab_panels[tk].visible = (tk == tab)
		_set_nav_active(nav_btns[tk], tk == tab)
	if tab == "board":
		_lb_refresh()

# carte cliquable façon Aimlabs : icône + titre + description + info accent
func _card(icon_kind: String, title: String, sub: String, extra: String, min_h: float) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb_n := UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 0)
	var sb_h := UIKit.panel_style(UIKit.COL_PANEL2, UIKit.COL_ACCENT, 10, 0)
	var sb_p := UIKit.panel_style(UIKit.COL_GROUND, UIKit.COL_ACCENT, 10, 0)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_p)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for mrg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(mrg, 18)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := IconDraw.new(icon_kind)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t1 := UIKit.label(title, 16, UIKit.COL_TEXT, true)
	var t2 := UIKit.label(sub, 12, UIKit.COL_MUTED)
	t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var t3 := UIKit.label(extra, 12, UIKit.COL_ACCENT2, true)
	for n in [t1, t2, t3]:
		v.add_child(n)
	h.add_child(ic)
	h.add_child(v)
	m.add_child(h)
	b.add_child(m)
	return {"btn": b, "extra": t3}

func _build_tab_train() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UIKit.label("ENTRAÎNEMENT", 22, UIKit.COL_TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.label("durée", 12, UIKit.COL_MUTED, true))
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 13)
		db.pressed.connect(_set_duration.bind(d))
		dur_btns.append(db)
		head.add_child(db)
	v.add_child(head)
	v.add_child(UIKit.label("%d exercices en %d packs · difficulté ◆ à ◆◆◆◆◆ · records par durée · la sens et le fov du jeu sélectionné s'appliquent" % [MODE_ORDER.size(), PACKS.size()], 12, UIKit.COL_MUTED))

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var packs_v := VBoxContainer.new()
	packs_v.add_theme_constant_override("separation", 18)
	packs_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(packs_v)

	for pack in PACKS:
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 12)
		ph.add_child(UIKit.label(pack["label"], 15, UIKit.COL_ACCENT, true))
		var pd := UIKit.label(pack["desc"], 11, UIKit.COL_MUTED, true)
		pd.size_flags_vertical = Control.SIZE_SHRINK_END
		ph.add_child(pd)
		packs_v.add_child(ph)

		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for mk in MODE_ORDER:
			var m: Dictionary = MODES[mk]
			if m["pack"] != pack["key"]:
				continue
			var c := _card(m["icon"], m["name"], m["desc"], "", 108.0)
			c["btn"].pressed.connect(_open_setup.bind(mk))
			mode_rec_lbls[mk] = c["extra"]
			grid.add_child(c["btn"])
		packs_v.add_child(grid)
	return v

# ============================================================
#  PLAYLISTS SOLO — routines nommées, exercices en ordre aléatoire
#  Chaque item garde ses propres paramètres (défaut = classé, perso = libre).
# ============================================================
func _build_tab_playlists() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UIKit.label("PLAYLISTS", 22, UIKit.COL_TEXT))
	var intro := UIKit.label("Compose tes propres routines : choisis des exercices, règle leurs paramètres si tu veux, nomme la playlist. À la lecture les exercices s'enchaînent dans un ordre aléatoire. Un exercice laissé aux paramètres par défaut reste classé ; personnalisé, il est libre.", 13, UIKit.COL_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(660, 0)
	v.add_child(intro)
	var nb := UIKit.btn("＋ NOUVELLE PLAYLIST", true, 14)
	nb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	nb.pressed.connect(_pl_new)
	v.add_child(nb)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	pl_list_box = VBoxContainer.new()
	pl_list_box.add_theme_constant_override("separation", 10)
	pl_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pl_list_box)
	_pl_load()
	_pl_render_list()
	return v

func _pl_load() -> void:
	var raw = _cfg_ref().get_value("playlists", "all", [])
	playlists = raw if raw is Array else []

func _pl_save() -> void:
	_cfg_ref().set_value("playlists", "all", playlists)
	_cfg_ref().save("user://senslab.cfg")

func _pl_render_list() -> void:
	if pl_list_box == null:
		return
	for ch in pl_list_box.get_children():
		ch.queue_free()
	if playlists.is_empty():
		pl_list_box.add_child(UIKit.label("Aucune playlist pour l'instant. Crée-en une avec « ＋ NOUVELLE PLAYLIST ».", 13, UIKit.COL_MUTED))
		return
	for i in playlists.size():
		var pl: Dictionary = playlists[i]
		var items: Array = pl.get("items", [])
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		pc.add_child(row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(UIKit.label(str(pl.get("name", "playlist")), 16, UIKit.COL_TEXT, true))
		var names: Array = []
		var custn := 0
		for it in items:
			names.append(str(MODES.get(str(it.get("mk", "")), {}).get("name", "?")))
			if not (it.get("cust", {}) as Dictionary).is_empty():
				custn += 1
		var sub := "%d exercice%s · %d s · ordre aléatoire" % [items.size(), "s" if items.size() > 1 else "", int(pl.get("dur", 60))]
		if custn > 0:
			sub += " · %d personnalisé%s" % [custn, "s" if custn > 1 else ""]
		info.add_child(UIKit.label(sub, 11, UIKit.COL_ACCENT2, true))
		var lst := UIKit.label((" · ".join(names)) if not names.is_empty() else "vide", 11, UIKit.COL_MUTED)
		lst.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(lst)
		row.add_child(info)
		var play := UIKit.btn("JOUER", true, 12)
		play.disabled = items.is_empty()
		play.pressed.connect(_pl_play.bind(i))
		row.add_child(play)
		var edit := UIKit.btn("MODIFIER", false, 12)
		edit.pressed.connect(_pl_edit.bind(i))
		row.add_child(edit)
		var del := UIKit.btn("✕", false, 12)
		del.pressed.connect(_pl_delete.bind(i))
		row.add_child(del)
		pl_list_box.add_child(pc)

func _pl_delete(i: int) -> void:
	if i < 0 or i >= playlists.size():
		return
	playlists.remove_at(i)
	_pl_save()
	_pl_render_list()

# ---- éditeur ----
func _build_pl_editor() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 12, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(680, 0)
	card.add_child(v)
	pl_edit_title = UIKit.label("", 20, UIKit.COL_TEXT, true)
	v.add_child(pl_edit_title)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 12)
	var nlab := UIKit.label("NOM", 12, UIKit.COL_MUTED, true)
	nlab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(nlab)
	pl_name_in = UIKit.input("")
	pl_name_in.placeholder_text = "ex. Échauffement flick"
	pl_name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(pl_name_in)
	v.add_child(nrow)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	drow.add_child(UIKit.label("DURÉE PAR EXERCICE", 11, UIKit.COL_MUTED, true))
	pl_dur_btns = []
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 12)
		db.pressed.connect(func():
			pl_edit_dur = d
			_pl_sync_dur())
		pl_dur_btns.append(db)
		drow.add_child(db)
	v.add_child(drow)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("EXERCICES  ·  joués dans un ordre aléatoire", 12, UIKit.COL_ACCENT, true))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 250)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	pl_items_box = VBoxContainer.new()
	pl_items_box.add_theme_constant_override("separation", 5)
	pl_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(pl_items_box)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 10)
	pl_add_opt = OptionButton.new()
	pl_add_opt.focus_mode = Control.FOCUS_NONE
	pl_add_opt.add_theme_font_override("font", UIKit.mono())
	pl_add_opt.add_theme_font_size_override("font_size", 13)
	pl_add_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pack_labels := {}
	for pack in PACKS:
		pack_labels[pack["key"]] = pack["label"]
	for i in MODE_ORDER.size():
		var m: Dictionary = MODES[MODE_ORDER[i]]
		pl_add_opt.add_item("%s · %s ◆%d" % [pack_labels[m["pack"]], m["name"], m["diff"]], i)
	arow.add_child(pl_add_opt)
	var addb := UIKit.btn("AJOUTER", false, 12)
	addb.pressed.connect(_pl_add_item)
	arow.add_child(addb)
	v.add_child(arow)
	v.add_child(HSeparator.new())
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var save := UIKit.btn("ENREGISTRER", true, 14)
	save.pressed.connect(_pl_save_editor)
	var cancel := UIKit.btn("ANNULER", false, 13)
	cancel.pressed.connect(_pl_cancel_editor)
	for b in [save, cancel]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	v.add_child(actions)
	pl_edit_panel = UIKit.overlay_wrap(card)
	ui.add_child(pl_edit_panel)

func _pl_sync_dur() -> void:
	for i in DURATIONS.size():
		UIKit.set_btn_selected(pl_dur_btns[i], DURATIONS[i] == pl_edit_dur)

func _pl_new() -> void:
	pl_edit_idx = -1
	pl_edit_name = ""
	pl_edit_dur = t_dur
	pl_edit_items = []
	_pl_open_editor()

func _pl_edit(i: int) -> void:
	if i < 0 or i >= playlists.size():
		return
	var pl: Dictionary = playlists[i]
	pl_edit_idx = i
	pl_edit_name = str(pl.get("name", ""))
	pl_edit_dur = int(pl.get("dur", 60))
	pl_edit_items = []
	for it in pl.get("items", []):
		pl_edit_items.append({"mk": str(it.get("mk", "")), "cust": (it.get("cust", {}) as Dictionary).duplicate(true)})
	_pl_open_editor()

func _pl_open_editor() -> void:
	pl_edit_title.text = "NOUVELLE PLAYLIST" if pl_edit_idx < 0 else "MODIFIER LA PLAYLIST"
	pl_name_in.text = pl_edit_name
	_pl_sync_dur()
	_pl_edit_render()
	_show_only(pl_edit_panel)

func _pl_edit_render() -> void:
	for ch in pl_items_box.get_children():
		ch.queue_free()
	if pl_edit_items.is_empty():
		pl_items_box.add_child(UIKit.label("Ajoute des exercices avec le menu ci-dessous.", 12, UIKit.COL_MUTED))
		return
	for i in pl_edit_items.size():
		var it: Dictionary = pl_edit_items[i]
		var m: Dictionary = MODES[str(it["mk"])]
		var cust: Dictionary = it.get("cust", {})
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_GROUND, UIKit.COL_LINE, 8, 10))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		pc.add_child(row)
		var idx := UIKit.label("%d" % (i + 1), 12, UIKit.COL_MUTED, true)
		idx.custom_minimum_size = Vector2(22, 0)
		idx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(idx)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_child(UIKit.label("%s  %s" % [m["name"], "◆".repeat(int(m["diff"]))], 13, UIKit.COL_TEXT, true))
		info.add_child(UIKit.label(_pl_item_summary(str(it["mk"]), cust), 11, UIKit.COL_ACCENT2 if not cust.is_empty() else UIKit.COL_MUTED, true))
		row.add_child(info)
		var pb := UIKit.btn("PARAMÈTRES", false, 11)
		pb.pressed.connect(_pl_item_params.bind(i))
		row.add_child(pb)
		var rm := UIKit.btn("✕", false, 11)
		rm.pressed.connect(_pl_item_remove.bind(i))
		row.add_child(rm)
		pl_items_box.add_child(pc)

func _pl_item_summary(mk: String, cust: Dictionary) -> String:
	if cust.is_empty():
		return "paramètres par défaut · classé"
	var parts: Array = []
	for spec in _setup_specs(mk):
		if cust.has(spec["key"]):
			parts.append("%s %s" % [str(spec["label"]).to_lower(), _fmt_param(spec, float(cust[spec["key"]]))])
	return "personnalisé · " + ((", ".join(parts)) if not parts.is_empty() else "modifié")

func _pl_add_item() -> void:
	pl_edit_items.append({"mk": MODE_ORDER[pl_add_opt.selected], "cust": {}})
	_pl_edit_render()

func _pl_item_remove(i: int) -> void:
	if i < 0 or i >= pl_edit_items.size():
		return
	pl_edit_items.remove_at(i)
	_pl_edit_render()

func _pl_item_params(i: int) -> void:
	if i < 0 or i >= pl_edit_items.size():
		return
	setup_item_idx = i
	var it: Dictionary = pl_edit_items[i]
	_open_setup(str(it["mk"]), false, "playlist", it.get("cust", {}))

func _pl_save_editor() -> void:
	var nm := pl_name_in.text.strip_edges()
	if nm == "":
		nm = "Playlist %d" % (playlists.size() + 1)
	var pl := {"name": nm.substr(0, 40), "dur": pl_edit_dur, "items": pl_edit_items.duplicate(true)}
	if pl_edit_idx < 0:
		playlists.append(pl)
	else:
		playlists[pl_edit_idx] = pl
	_pl_save()
	_pl_render_list()
	_show_only(menu_panel)
	_show_tab("playlists")

func _pl_cancel_editor() -> void:
	_show_only(menu_panel)
	_show_tab("playlists")

# ---- lecture ----
func _pl_play(i: int) -> void:
	if i < 0 or i >= playlists.size():
		return
	var pl: Dictionary = playlists[i]
	var items: Array = pl.get("items", [])
	if items.is_empty():
		return
	pl_queue = items.duplicate(true)
	pl_queue.shuffle()
	pl_i = 0
	pl_active = true
	pl_play_name = str(pl.get("name", "playlist"))
	pl_play_dur = int(pl.get("dur", 60))
	_pl_start_current()

func _pl_start_current() -> void:
	var it: Dictionary = pl_queue[pl_i]
	custom = (it.get("cust", {}) as Dictionary).duplicate(true)
	_set_duration(pl_play_dur)
	_start_train(str(it["mk"]))

func _pl_next() -> void:
	if not pl_active:
		_goto_menu()
		return
	pl_i += 1
	if pl_i >= pl_queue.size():
		_pl_stop()
		return
	_pl_start_current()

func _pl_stop() -> void:
	pl_active = false
	pl_queue = []
	pl_i = 0
	_goto_menu()
	_show_tab("playlists")

# ============================================================
#  DÉFI MULTIJOUEUR — rooms 1v1vX (16 max)
# ============================================================
func _build_tab_duel() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.add_child(UIKit.label("DÉFI 1V1VX", 22, UIKit.COL_TEXT))
	var intro := UIKit.label("Crée une room, partage le code : tout le monde joue les mêmes exercices en même temps. Le meilleur score de chaque round marque 1 point. Jusqu'à %d joueurs, pas de minimum." % ROOM_MAX, 13, UIKit.COL_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(600, 0)
	v.add_child(intro)
	duel_status = UIKit.label("", 12, UIKit.COL_ACCENT2, true)
	v.add_child(duel_status)

	# ---- création / rejoindre ----
	duel_setup = VBoxContainer.new()
	duel_setup.add_theme_constant_override("separation", 12)
	v.add_child(duel_setup)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 10)
	var cbtn := UIKit.btn("CRÉER UNE ROOM", true, 14)
	cbtn.pressed.connect(_duel_create)
	crow.add_child(cbtn)
	crow.add_child(UIKit.label("durée des rounds", 12, UIKit.COL_MUTED, true))
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 12)
		db.pressed.connect(func():
			duel_dur = d
			for i in DURATIONS.size():
				UIKit.set_btn_selected(duel_dur_btns[i], DURATIONS[i] == duel_dur))
		duel_dur_btns.append(db)
		crow.add_child(db)
	duel_open_btn = UIKit.btn("PLAYLIST OUVERTE ✓", false, 12)
	duel_open_btn.pressed.connect(func():
		duel_open = not duel_open
		duel_open_btn.text = "PLAYLIST OUVERTE ✓" if duel_open else "PLAYLIST HÔTE SEUL")
	crow.add_child(duel_open_btn)
	duel_setup.add_child(crow)
	var jrow := HBoxContainer.new()
	jrow.add_theme_constant_override("separation", 10)
	duel_join_in = UIKit.input("")
	duel_join_in.placeholder_text = "code de room (ex. K4TR7)"
	duel_join_in.custom_minimum_size = Vector2(240, 0)
	jrow.add_child(duel_join_in)
	var jbtn := UIKit.btn("REJOINDRE", false, 14)
	jbtn.pressed.connect(_duel_join)
	jrow.add_child(jbtn)
	duel_setup.add_child(jrow)

	# ---- lobby ----
	duel_lobby = VBoxContainer.new()
	duel_lobby.add_theme_constant_override("separation", 12)
	duel_lobby.visible = false
	v.add_child(duel_lobby)
	duel_code_lbl = UIKit.label("", 34, UIKit.COL_ACCENT2, true)
	duel_lobby.add_child(duel_code_lbl)
	duel_count_lbl = UIKit.label("", 16, UIKit.COL_ACCENT, true)
	duel_lobby.add_child(duel_count_lbl)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	duel_lobby.add_child(cols)
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 6)
	pcol.custom_minimum_size = Vector2(300, 0)
	pcol.add_child(UIKit.label("JOUEURS & POINTS", 12, UIKit.COL_ACCENT, true))
	duel_players_grid = GridContainer.new()
	duel_players_grid.columns = 3
	duel_players_grid.add_theme_constant_override("h_separation", 22)
	duel_players_grid.add_theme_constant_override("v_separation", 3)
	pcol.add_child(duel_players_grid)
	cols.add_child(pcol)
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 6)
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mcol.add_child(UIKit.label("PLAYLIST", 12, UIKit.COL_ACCENT, true))
	duel_modes_list = VBoxContainer.new()
	duel_modes_list.add_theme_constant_override("separation", 3)
	mcol.add_child(duel_modes_list)
	duel_add_row = HBoxContainer.new()
	duel_add_row.add_theme_constant_override("separation", 10)
	duel_add_opt = OptionButton.new()
	duel_add_opt.focus_mode = Control.FOCUS_NONE
	duel_add_opt.add_theme_font_override("font", UIKit.mono())
	duel_add_opt.add_theme_font_size_override("font_size", 13)
	duel_add_opt.custom_minimum_size = Vector2(320, 0)
	var pack_labels := {}
	for pack in PACKS:
		pack_labels[pack["key"]] = pack["label"]
	for i in MODE_ORDER.size():
		var m: Dictionary = MODES[MODE_ORDER[i]]
		duel_add_opt.add_item("%s · %s ◆%d" % [pack_labels[m["pack"]], m["name"], m["diff"]], i)
	duel_add_row.add_child(duel_add_opt)
	var abtn := UIKit.btn("AJOUTER À LA PLAYLIST", false, 12)
	abtn.pressed.connect(_duel_add_mode)
	duel_add_row.add_child(abtn)
	mcol.add_child(duel_add_row)
	cols.add_child(mcol)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 10)
	duel_host_btn = UIKit.btn("", true, 14)
	duel_host_btn.pressed.connect(_duel_start_next)
	hrow.add_child(duel_host_btn)
	duel_finish_btn = UIKit.btn("TERMINER LE DÉFI", false, 13)
	duel_finish_btn.pressed.connect(func(): room.finish(room_code))
	hrow.add_child(duel_finish_btn)
	var lbtn := UIKit.btn("QUITTER LA ROOM", false, 13)
	lbtn.pressed.connect(_duel_leave)
	hrow.add_child(lbtn)
	duel_lobby.add_child(hrow)
	return v

func _rsrv_now() -> float:
	return Time.get_unix_time_from_system() + room_srv_offset

func _duel_create() -> void:
	if pseudo == "":
		duel_status.text = "⚠ définis d'abord un pseudo dans RÉGLAGES"
		return
	var chars := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in 5:
		code += chars[randi() % chars.length()]
	duel_status.text = "création de la room…"
	room_is_host = true
	room_code = code
	room.create(code, pseudo, duel_dur, duel_open)

func _duel_join() -> void:
	if pseudo == "":
		duel_status.text = "⚠ définis d'abord un pseudo dans RÉGLAGES"
		return
	var code := duel_join_in.text.strip_edges().to_upper()
	if code.length() < 4:
		duel_status.text = "⚠ code de room invalide"
		return
	duel_status.text = "connexion à la room…"
	room_is_host = false
	room_code = code
	room.join(code, pseudo)

func _duel_enter_lobby() -> void:
	duel_setup.visible = false
	duel_lobby.visible = true
	room_launched = -1
	room.srv_now()
	room.fetch(room_code)
	room_poll.start()

func _duel_leave() -> void:
	if room_code != "":
		room.leave(room_code, pseudo)
	room_code = ""
	room_data = {}
	room_poll.stop()
	duel_lobby.visible = false
	duel_setup.visible = true
	duel_status.text = "tu as quitté la room"

func _on_room_op(op: String, ok: bool) -> void:
	match op:
		"create":
			if ok:
				duel_status.text = "room créée — partage le code !"
				_duel_enter_lobby()
			else:
				room_code = ""
				duel_status.text = "⚠ création impossible — vérifie ta connexion (et le SQL rooms côté Supabase)"
		"join":
			if ok:
				duel_status.text = "room rejointe"
				_duel_enter_lobby()
			else:
				room_code = ""
				duel_status.text = "⚠ room introuvable ou pleine (%d max)" % ROOM_MAX
		"addmode", "start", "finish":
			if room_code != "":
				room.fetch(room_code)
		"score":
			if room_code != "":
				room.fetch(room_code)

func _duel_modes_sorted() -> Array:
	var arr: Array = room_data.get("room_modes", [])
	var out := arr.duplicate()
	out.sort_custom(func(a, b): return int(a.get("ord", 0)) < int(b.get("ord", 0)))
	return out

func _duel_add_mode() -> void:
	if room_code == "":
		return
	var can_add: bool = room_is_host or bool(room_data.get("open_playlist", true))
	if not can_add:
		duel_status.text = "⚠ seul l'hôte peut modifier la playlist"
		return
	var mk: String = MODE_ORDER[duel_add_opt.selected]
	room.add_mode(room_code, mk, pseudo, _duel_modes_sorted().size())

func _duel_start_next() -> void:
	if not room_is_host or room_code == "":
		return
	var modes_arr := _duel_modes_sorted()
	if modes_arr.is_empty():
		duel_status.text = "⚠ ajoute au moins un exercice à la playlist"
		return
	var next: int = int(room_data.get("round_i", -1)) + 1
	if str(room_data.get("state", "")) == "lobby":
		next = 0
	if next >= modes_arr.size():
		return
	room.start(room_code, next)

# un round est terminé si sa fenêtre de jeu est passée ou si tous ont un score
func _duel_round_over(r: int, players: Array, scores: Array) -> bool:
	var round_i := int(room_data.get("round_i", -1))
	if r < round_i or str(room_data.get("state", "")) == "done":
		return true
	if r != round_i:
		return false
	var start_e: float = float(room_data.get("start_epoch") if room_data.get("start_epoch") != null else 0.0)
	if start_e > 0.0 and _rsrv_now() > start_e + float(room_data.get("duration", 30)) + 6.0:
		return true
	var n := 0
	for s in scores:
		if int(s.get("round_i", -1)) == r:
			n += 1
	return n >= players.size() and n > 0

func _on_room_state(ok: bool, data: Dictionary) -> void:
	if not ok or room_code == "":
		return
	room_data = data
	_duel_render()
	# lancement synchronisé du round courant
	if str(data.get("state", "")) != "countdown":
		return
	var round_i := int(data.get("round_i", -1))
	var start_e: float = float(data.get("start_epoch") if data.get("start_epoch") != null else 0.0)
	if round_i < 0 or start_e <= 0.0 or round_i == room_launched:
		return
	var remaining := start_e - _rsrv_now()
	if remaining < -3.0 or remaining > 30.0:
		return
	if mode != Mode.MENU and mode != Mode.T_RESULTS:
		return
	var modes_arr := _duel_modes_sorted()
	if round_i >= modes_arr.size():
		return
	var mk := str(modes_arr[round_i].get("mode", ""))
	if not MODES.has(mk):
		return
	room_launched = round_i
	room_played = round_i
	room_active = true
	t_dur = int(data.get("duration", 30))
	custom = {}   # défi = paramètres par défaut pour tout le monde
	_start_train(mk)
	count_timer = clampf(remaining, 0.8, 10.0)
	cnt_round_lbl.text = "DÉFI · ROUND %d/%d · %s" % [round_i + 1, modes_arr.size(), MODES[mk]["name"]]

func _duel_render() -> void:
	if room_data.is_empty():
		return
	var players: Array = room_data.get("room_players", [])
	var scores: Array = room_data.get("room_scores", [])
	var modes_arr := _duel_modes_sorted()
	var state := str(room_data.get("state", "lobby"))
	var round_i := int(room_data.get("round_i", -1))
	duel_code_lbl.text = "ROOM  %s" % room_code
	# points : le meilleur score de chaque round terminé vaut 1 point
	var wins := {}
	var last_scores := {}
	for p in players:
		wins[str(p.get("player", "?"))] = 0
	for r in modes_arr.size():
		if not _duel_round_over(r, players, scores):
			continue
		var best := -1
		for s in scores:
			if int(s.get("round_i", -1)) == r:
				best = maxi(best, int(s.get("score", 0)))
		if best < 0:
			continue
		for s in scores:
			if int(s.get("round_i", -1)) == r and int(s.get("score", 0)) == best:
				var pl := str(s.get("player", "?"))
				wins[pl] = int(wins.get(pl, 0)) + 1
	# statut / compte à rebours
	var host := str(room_data.get("host", ""))
	if state == "done":
		var champ := ""
		var champ_w := -1
		for pl in wins:
			if int(wins[pl]) > champ_w:
				champ_w = int(wins[pl])
				champ = pl
		duel_count_lbl.text = "DÉFI TERMINÉ — vainqueur : %s (%d pts)" % [champ, champ_w] if champ_w > 0 else "DÉFI TERMINÉ"
	elif state == "countdown":
		var start_e: float = float(room_data.get("start_epoch") if room_data.get("start_epoch") != null else 0.0)
		var remaining := start_e - _rsrv_now()
		if remaining > 0.0:
			duel_count_lbl.text = "ROUND %d/%d — départ dans %d s…" % [round_i + 1, modes_arr.size(), int(ceil(remaining))]
		elif not _duel_round_over(round_i, players, scores):
			duel_count_lbl.text = "ROUND %d/%d en cours…" % [round_i + 1, modes_arr.size()]
		else:
			duel_count_lbl.text = "round %d/%d terminé — en attente de l'hôte (%s)" % [round_i + 1, modes_arr.size(), host]
	else:
		duel_count_lbl.text = "%d/%d joueurs — l'hôte %s lance quand tout le monde est là" % [players.size(), ROOM_MAX, host]
	# joueurs
	for ch in duel_players_grid.get_children():
		ch.queue_free()
	for s in scores:
		if int(s.get("round_i", -1)) == round_i:
			last_scores[str(s.get("player", ""))] = int(s.get("score", 0))
	var ranked := wins.keys()
	ranked.sort_custom(func(a, b): return int(wins[a]) > int(wins[b]))
	for h in ["PSEUDO", "POINTS", "DERNIER SCORE"]:
		duel_players_grid.add_child(UIKit.label(h, 11, UIKit.COL_MUTED, true))
	for pl in ranked:
		var me: bool = (str(pl) == pseudo)
		var col := UIKit.COL_ACCENT2 if me else UIKit.COL_TEXT
		var host_mark := " ★" if pl == host else ""
		duel_players_grid.add_child(UIKit.label(str(pl) + host_mark, 13, col, true))
		duel_players_grid.add_child(UIKit.label(str(wins[pl]), 13, col, true))
		duel_players_grid.add_child(UIKit.label(str(last_scores.get(pl, "—")), 13, col, true))
	# playlist
	for ch in duel_modes_list.get_children():
		ch.queue_free()
	for r in modes_arr.size():
		var mk := str(modes_arr[r].get("mode", ""))
		var mname: String = MODES[mk]["name"] if MODES.has(mk) else mk
		var line := "%d. %s" % [r + 1, mname]
		var col2 := UIKit.COL_MUTED
		if _duel_round_over(r, players, scores):
			var best := -1
			var bestp := ""
			for s in scores:
				if int(s.get("round_i", -1)) == r and int(s.get("score", 0)) > best:
					best = int(s.get("score", 0))
					bestp = str(s.get("player", ""))
			line += "  →  %s (%d)" % [bestp, best] if best >= 0 else "  →  aucun score"
			col2 = UIKit.COL_TEXT
		elif r == round_i and state == "countdown":
			line += "  ◄ en cours"
			col2 = UIKit.COL_ACCENT
		var by := str(modes_arr[r].get("added_by", ""))
		if by != "" and by != str(room_data.get("host", "")):
			line += "   (ajouté par %s)" % by
		duel_modes_list.add_child(UIKit.label(line, 13, col2, true))
	if modes_arr.is_empty():
		duel_modes_list.add_child(UIKit.label("playlist vide — ajoute des exercices ci-dessous", 12, UIKit.COL_MUTED))
	# contrôles
	duel_add_row.visible = state != "done" and (room_is_host or bool(room_data.get("open_playlist", true)))
	var cur_over := round_i < 0 or _duel_round_over(round_i, players, scores)
	var next_round := 0 if state == "lobby" else round_i + 1
	duel_host_btn.visible = room_is_host and state != "done" and cur_over and next_round < modes_arr.size()
	duel_host_btn.text = "LANCER LE ROUND %d/%d" % [next_round + 1, maxi(modes_arr.size(), 1)]
	duel_finish_btn.visible = room_is_host and state != "done" and round_i >= 0

func _build_tab_finder() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.add_child(UIKit.label("SENS FINDER", 22, UIKit.COL_TEXT))
	var intro := UIKit.label("Calibration à l'aveugle : chaque round modifie ta sensibilité sans te le dire. Le moteur mesure ton throughput effectif (ISO 9241-9 : largeur effective We = 4,133·σ des impacts), retire l'effet d'apprentissage, ajuste un processus gaussien sur ta courbe de performance, place les rounds adaptatifs par optimisation bayésienne (UCB) et borne la plage recommandée par bootstrap — avec les équivalents pour les 5 jeux.", 13, UIKit.COL_MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(600, 0)
	v.add_child(intro)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for pk in ["rapide", "standard", "precision"]:
		var p: Dictionary = PROTOCOLS[pk]
		var c := _card(pk, "%s · %s" % [p["label"], p["time"]], p["desc"],
			"%d rounds" % (p["base"].size() + int(p["refine"]) + int(p["confirm"])), 132.0)
		c["btn"].pressed.connect(_start_finder.bind(pk))
		row.add_child(c["btn"])
	v.add_child(row)
	var note := UIKit.label("Conseil : joue chaque round comme en ranked. Plus le protocole est long, plus le R² et la plage recommandée sont fiables.", 12, UIKit.COL_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	return v

func _build_tab_board() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UIKit.label("CLASSEMENT", 22, UIKit.COL_TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var refresh := UIKit.btn("ACTUALISER", false, 12)
	refresh.pressed.connect(_lb_refresh)
	head.add_child(refresh)
	v.add_child(head)

	# ---- bascule par exercice / général ----
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	lb_view_btns = []
	for entry in [["PAR EXERCICE", false], ["GÉNÉRAL", true]]:
		var vb := UIKit.btn(str(entry[0]), false, 12)
		vb.pressed.connect(_lb_set_view.bind(bool(entry[1])))
		lb_view_btns.append(vb)
		vrow.add_child(vb)
	v.add_child(vrow)

	lb_ex_box = VBoxContainer.new()
	lb_ex_box.add_theme_constant_override("separation", 8)
	v.add_child(lb_ex_box)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	mrow.add_child(UIKit.label("exercice", 12, UIKit.COL_MUTED, true))
	lb_mode_opt = OptionButton.new()
	lb_mode_opt.focus_mode = Control.FOCUS_NONE
	lb_mode_opt.add_theme_font_override("font", UIKit.mono())
	lb_mode_opt.add_theme_font_size_override("font_size", 13)
	lb_mode_opt.custom_minimum_size = Vector2(340, 0)
	var pack_labels := {}
	for pack in PACKS:
		pack_labels[pack["key"]] = pack["label"]
	for i in MODE_ORDER.size():
		var m: Dictionary = MODES[MODE_ORDER[i]]
		lb_mode_opt.add_item("%s · %s" % [pack_labels[m["pack"]], m["name"]], i)
	lb_mode_opt.item_selected.connect(func(i: int):
		lb_mode = MODE_ORDER[i]
		_lb_refresh())
	mrow.add_child(lb_mode_opt)
	lb_ex_box.add_child(mrow)

	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 12)
		db.pressed.connect(_lb_set_dur.bind(d))
		lb_dur_btns.append(db)
		drow.add_child(db)
	lb_ex_box.add_child(drow)

	lb_status = UIKit.label("", 12, UIKit.COL_MUTED, true)
	v.add_child(lb_status)

	lb_grid = GridContainer.new()
	lb_grid.columns = 3
	lb_grid.add_theme_constant_override("h_separation", 30)
	lb_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(lb_grid)
	return v

func _build_tab_patch() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := UIKit.label("PATCH NOTES", 22, UIKit.COL_TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UIKit.label("version actuelle v" + Updater.VERSION, 12, UIKit.COL_ACCENT2, true))
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for entry in CHANGELOG:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 16))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)
		pc.add_child(col)
		var vtag := "v%s" % str(entry["v"])
		if str(entry["v"]) == Updater.VERSION:
			vtag += "  ·  actuelle"
		col.add_child(UIKit.label(vtag, 15, UIKit.COL_ACCENT, true))
		for note in entry["notes"]:
			var line := UIKit.label("•  " + str(note), 12, UIKit.COL_TEXT)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(640, 0)
			col.add_child(line)
		list.add_child(pc)
	return v

func _lb_set_dur(d: int) -> void:
	lb_dur = d
	_lb_refresh()

func _lb_set_view(general: bool) -> void:
	lb_general = general
	_lb_refresh()

func _lb_refresh() -> void:
	for i in lb_view_btns.size():
		UIKit.set_btn_selected(lb_view_btns[i], (i == 1) == lb_general)
	lb_ex_box.visible = not lb_general
	var mi := MODE_ORDER.find(lb_mode)
	if mi >= 0 and lb_mode_opt.selected != mi:
		lb_mode_opt.select(mi)
	for i in DURATIONS.size():
		UIKit.set_btn_selected(lb_dur_btns[i], DURATIONS[i] == lb_dur)
	for ch in lb_grid.get_children():
		ch.queue_free()
	if not lb.configured():
		lb_status.text = "classement en ligne non configuré dans cette version"
		return
	lb_status.text = "chargement…"
	if lb_general:
		lb.fetch_all(LB_GEN_DUR)
	else:
		lb.fetch_top(lb_mode, lb_dur)

# classement général : note /100 par joueur = moyenne, sur les 5 catégories, de
# sa note de catégorie (moyenne de ses scores ramenés sur 100 vs le meilleur
# mondial, sur les 3 exercices les plus joués de la catégorie). 60 s de référence.
func _on_lb_all(ok: bool, rows: Array) -> void:
	if not lb_general:
		return
	for ch in lb_grid.get_children():
		ch.queue_free()
	if not ok:
		lb_status.text = "⚠ classement injoignable — vérifie ta connexion"
		return
	var standings := _compute_general(rows)
	if standings.is_empty():
		lb_status.text = "pas encore assez de scores pour un classement général (60 s)"
		return
	var me_txt := "tu joues en tant que « %s »" % pseudo if pseudo != "" else "⚠ aucun pseudo défini (RÉGLAGES)"
	lb_status.text = "note /100 · moyenne des 3 exercices les plus joués de chaque catégorie · 60 s — %s" % me_txt
	_fill_general_grid(standings)

func _compute_general(rows: Array) -> Array:
	# 1) meilleur score par joueur et par exercice
	var by_mode := {}
	for r in rows:
		var mk := str(r.get("mode", ""))
		if not MODES.has(mk):
			continue
		var pl := str(r.get("player", ""))
		if pl == "":
			continue
		var sc := float(r.get("score", 0))
		if not by_mode.has(mk):
			by_mode[mk] = {}
		if not by_mode[mk].has(pl) or sc > float(by_mode[mk][pl]):
			by_mode[mk][pl] = sc
	# 2) les 3 exercices les plus joués (nb de joueurs classés) par catégorie
	var selected := {}
	for pack in PACKS:
		var cand: Array = []
		for mk in MODE_ORDER:
			if str(MODES[mk]["pack"]) == str(pack["key"]) and by_mode.has(mk):
				cand.append(mk)
		cand.sort_custom(func(a, b): return int(by_mode[a].size()) > int(by_mode[b].size()))
		selected[pack["key"]] = cand.slice(0, 3)
	# 3) note normalisée /100 par exercice, cumulée par joueur et par catégorie
	var cat := {}          # joueur -> {pack: [somme, nb]}
	var players := {}
	for pack in PACKS:
		for mk in selected[pack["key"]]:
			var best := 0.0
			for pl in by_mode[mk]:
				best = maxf(best, float(by_mode[mk][pl]))
			if best <= 0.0:
				continue
			for pl in by_mode[mk]:
				var pts := float(by_mode[mk][pl]) / best * 100.0
				players[pl] = true
				if not cat.has(pl):
					cat[pl] = {}
				if not cat[pl].has(pack["key"]):
					cat[pl][pack["key"]] = [0.0, 0]
				cat[pl][pack["key"]][0] += pts
				cat[pl][pack["key"]][1] += 1
	# 4) note générale = moyenne des notes de catégorie sur les 5 catégories
	var out: Array = []
	var ncat := PACKS.size()
	for pl in players:
		var total := 0.0
		var covered := 0
		for pack in PACKS:
			if cat[pl].has(pack["key"]):
				var e: Array = cat[pl][pack["key"]]
				total += e[0] / float(e[1])
				covered += 1
		out.append({"player": pl, "note": total / float(ncat), "cov": covered})
	out.sort_custom(func(a, b): return float(a["note"]) > float(b["note"]))
	return out

func _fill_general_grid(standings: Array) -> void:
	lb_grid.columns = 4
	for h in ["#", "PSEUDO", "NOTE /100", "CATÉGORIES"]:
		lb_grid.add_child(UIKit.label(h, 11, UIKit.COL_MUTED, true))
	for i in mini(standings.size(), 20):
		var s: Dictionary = standings[i]
		var me: bool = str(s["player"]) == pseudo and pseudo != ""
		var col := UIKit.COL_ACCENT2 if me else (UIKit.COL_TEXT if i < 3 else UIKit.COL_MUTED)
		lb_grid.add_child(UIKit.label("%d" % (i + 1), 13, col, true))
		lb_grid.add_child(UIKit.label(str(s["player"]), 13, col, true))
		lb_grid.add_child(UIKit.label("%.1f" % float(s["note"]), 13, col, true))
		lb_grid.add_child(UIKit.label("%d/%d" % [int(s["cov"]), PACKS.size()], 13, col, true))

func _on_lb_top(ok: bool, rows: Array) -> void:
	# en vue générale sur l'onglet, ignorer une réponse par-exercice tardive
	if lb_general and mode != Mode.T_RESULTS:
		return
	for ch in lb_grid.get_children():
		ch.queue_free()
	if not ok:
		lb_status.text = "⚠ classement injoignable — vérifie ta connexion"
		if mode == Mode.T_RESULTS:
			dash_lb_status.text = "⚠ classement injoignable"
		return
	if rows.is_empty():
		lb_status.text = "aucun score en %s · %d s — sois le premier !" % [MODES[lb_mode]["name"], lb_dur]
		if mode == Mode.T_RESULTS:
			dash_lb_status.text = "aucun score encore — le tien sera peut-être le premier !"
		return
	var me_txt := "tu joues en tant que « %s »" % pseudo if pseudo != "" else "⚠ aucun pseudo défini (RÉGLAGES) — tes scores ne sont pas envoyés"
	lb_status.text = "%s · %d s · top %d — %s" % [MODES[lb_mode]["name"], lb_dur, rows.size(), me_txt]
	_fill_lb_grid(lb_grid, rows, rows.size())
	if mode == Mode.T_RESULTS:
		dash_lb_status.text = "%s · %d s · meilleur score par joueur" % [MODES[lb_mode]["name"], lb_dur]
		for ch in dash_lb_grid.get_children():
			ch.queue_free()
		_fill_lb_grid(dash_lb_grid, rows, 10, false)

func _fill_lb_grid(grid: GridContainer, rows: Array, limit: int, full: bool = true) -> void:
	var is_click: bool = str(MODES.get(lb_mode, {}).get("type", "click")) == "click"
	var headers := ["#", "PSEUDO", "SCORE"]
	if full:
		headers.append("PRÉCISION")
		headers.append("SÉRIE" if is_click else "SUR CIBLE")
	headers.append("REPLAY")
	grid.columns = headers.size()
	for h in headers:
		grid.add_child(UIKit.label(h, 11, UIKit.COL_MUTED, true))
	for i in mini(rows.size(), limit):
		var r: Dictionary = rows[i]
		var me: bool = str(r.get("player", "")) == pseudo and pseudo != ""
		var col := UIKit.COL_ACCENT2 if me else (UIKit.COL_TEXT if i < 3 else UIKit.COL_MUTED)
		grid.add_child(UIKit.label("%d" % (i + 1), 13, col, true))
		grid.add_child(UIKit.label(str(r.get("player", "?")), 13, col, true))
		grid.add_child(UIKit.label(str(int(r.get("score", 0))), 13, col, true))
		# précision (%) et série max, si l'info est disponible (v1.17+)
		if full:
			var acc = r.get("acc", null)
			grid.add_child(UIKit.label(("%d%%" % int(round(float(acc)))) if acc != null else "—", 13, col, true))
			if is_click:
				var stk = r.get("streak", null)
				grid.add_child(UIKit.label(str(int(stk)) if stk != null else "—", 13, col, true))
			else:
				grid.add_child(UIKit.label("—", 13, col, true))
		# replays téléchargeables pour le top 5
		if i < 5:
			var pb := UIKit.btn("▶ VOIR", false, 11)
			pb.pressed.connect(_lb_play_replay.bind(str(r.get("player", ""))))
			grid.add_child(pb)
		else:
			grid.add_child(UIKit.label("", 11, UIKit.COL_MUTED, true))

# ---- replays du top 5 : téléchargement puis lecture en visionneuse ----
func _lb_status_set(msg: String) -> void:
	if mode == Mode.T_RESULTS:
		dash_lb_status.text = msg
	else:
		lb_status.text = msg

func _lb_play_replay(pl: String) -> void:
	if pl == "":
		return
	_lb_status_set("téléchargement du replay de %s…" % pl)
	lb.fetch_replay(lb_mode, lb_dur, pl)

func _on_lb_replay(ok: bool, player: String, b64: String) -> void:
	if not ok or b64 == "":
		_lb_status_set("pas de replay pour %s (enregistrés à chaque record depuis la v1.8)" % player)
		return
	var d := _replay_unpack(b64)
	if d.is_empty():
		_lb_status_set("replay de %s illisible (version incompatible)" % player)
		return
	_open_replay_viewer(player, d)

func _open_replay_viewer(player: String, d: Dictionary) -> void:
	# on met le replay perso de côté pour le restaurer à la fermeture
	if mode == Mode.T_RESULTS:
		rvw_backup = {"samples": rec_samples, "tgt": rec_tgt, "on": rec_on,
			"targets": rec_targets, "clicks": rec_clicks, "cls": rp_cls,
			"dur": rp_dur, "cfg": t_cfg, "track": rp_overlay.track}
	else:
		rvw_backup = {}
	_rp_clear()
	rec_samples = d["samples"]
	rec_tgt = d["tgt"]
	rec_on = d["on"]
	rec_targets = d["targets"]
	rec_clicks = d["clicks"]
	t_cfg = {"type": d["type"], "r": d["r"], "trk": {"r": d["r"]}}
	rp_dur = maxf(float(d["dur"]), 0.5)
	rp_t = 0.0
	rp_playing = true
	rp_speed = 1.0
	_rp_classify(str(d["type"]) != "click")
	rvw_overlay.track = str(d["type"]) != "click"
	rvw_time_ctl.dur = rp_dur
	rvw_time_ctl.clicks = rec_clicks
	rvw_play_btn.text = "⏸ PAUSE"
	for i in rvw_speed_btns.size():
		UIKit.set_btn_selected(rvw_speed_btns[i], i == 1)
	var mname: String = MODES[d["mode"]]["name"] if MODES.has(d["mode"]) else str(d["mode"])
	rvw_title.text = "REPLAY — %s · %s · %d s · score %d" % [player, mname, int(d["dur"]), int(d["score"])]
	mode = Mode.R_VIEW
	hud_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only(rvw_panel)

func _rvw_close() -> void:
	_rp_clear()
	if not rvw_backup.is_empty():
		rec_samples = rvw_backup["samples"]
		rec_tgt = rvw_backup["tgt"]
		rec_on = rvw_backup["on"]
		rec_targets = rvw_backup["targets"]
		rec_clicks = rvw_backup["clicks"]
		rp_cls = rvw_backup["cls"]
		rp_dur = rvw_backup["dur"]
		t_cfg = rvw_backup["cfg"]
		rp_overlay.track = rvw_backup["track"]
		rvw_backup = {}
		rp_t = 0.0
		rp_playing = true
		mode = Mode.T_RESULTS
		_show_only(tres_panel)
	else:
		_goto_menu()
		_show_tab("board")

func _on_lb_submitted(ok: bool) -> void:
	if tres_net != null and mode == Mode.T_RESULTS:
		tres_net.text = "✓ score envoyé au classement" if ok else "⚠ envoi au classement échoué"
		dash_lb_status.text = "chargement du top…"
		lb.fetch_top(t_mode, t_dur)

func _build_tab_settings() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.add_child(UIKit.label("RÉGLAGES", 22, UIKit.COL_TEXT))
	v.add_child(UIKit.label("JEU", 11, UIKit.COL_MUTED, true))
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 10)
	for gk in GameDB.keys():
		var gb := UIKit.btn(GameDB.get_game(gk)["label"], false, 13)
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.pressed.connect(_select_game.bind(gk))
		game_btns[gk] = gb
		grow.add_child(gb)
	v.add_child(grow)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 14)
	var c0 := VBoxContainer.new()
	c0.add_child(UIKit.label("PSEUDO (CLASSEMENT)", 11, UIKit.COL_MUTED, true))
	in_pseudo = UIKit.input("")
	in_pseudo.placeholder_text = "ton pseudo"
	in_pseudo.max_length = 20
	in_pseudo.text_changed.connect(func(t: String):
		pseudo = t.strip_edges()
		_prefs_set("pseudo", pseudo)
		_refresh_derived())
	c0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(c0)
	c0.add_child(in_pseudo)
	var c2 := VBoxContainer.new()
	c2.add_child(UIKit.label("SENS EN JEU", 11, UIKit.COL_MUTED, true))
	in_sens = UIKit.input("0.4")
	c2.add_child(in_sens)
	var c3 := VBoxContainer.new()
	c3.add_child(UIKit.label("DPI SOURIS", 11, UIKit.COL_MUTED, true))
	in_dpi = UIKit.input("800")
	c3.add_child(in_dpi)
	var c4 := VBoxContainer.new()
	c4.add_child(UIKit.label("FOV", 11, UIKit.COL_MUTED, true))
	in_fov = UIKit.input("103")
	c4.add_child(in_fov)
	for c in [c2, c3, c4]:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(c)
	v.add_child(srow)
	fov_hint_lbl = UIKit.label("", 11, UIKit.COL_MUTED, true)
	derived_lbl = UIKit.label("", 13, UIKit.COL_ACCENT2, true)
	v.add_child(fov_hint_lbl)
	v.add_child(derived_lbl)
	in_sens.text_changed.connect(func(_t): _refresh_derived())
	in_dpi.text_changed.connect(func(_t): _refresh_derived())
	in_fov.text_changed.connect(func(_t): _refresh_derived())
	var note := UIKit.label("Raw input Windows natif — l'accélération du pointeur est ignorée, comme en jeu.\nSens et FOV sont mémorisés séparément pour chaque jeu.", 12, UIKit.COL_MUTED)
	v.add_child(note)

	# ---- affichage & performances ----
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("AFFICHAGE & PERFORMANCES", 11, UIKit.COL_MUTED, true))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 14)
	var dc1 := VBoxContainer.new()
	dc1.add_child(UIKit.label("FENÊTRE", 11, UIKit.COL_MUTED, true))
	var wlabels: Array = []
	for wm in WIN_MODES:
		wlabels.append(wm["label"])
	disp_size_opt = _mk_opt(wlabels, func(i: int):
		_prefs_set("win_mode", i)
		_apply_display())
	dc1.add_child(disp_size_opt)
	var dc2 := VBoxContainer.new()
	dc2.add_child(UIKit.label("ÉCRAN", 11, UIKit.COL_MUTED, true))
	var slabels: Array = []
	for i in DisplayServer.get_screen_count():
		slabels.append("ÉCRAN %d" % (i + 1))
	disp_screen_opt = _mk_opt(slabels, func(i: int):
		_prefs_set("screen", i)
		_apply_display())
	dc2.add_child(disp_screen_opt)
	var dc3 := VBoxContainer.new()
	dc3.add_child(UIKit.label("FPS MAX", 11, UIKit.COL_MUTED, true))
	var flabels: Array = []
	for f in FPS_CAPS:
		flabels.append("ILLIMITÉ" if f == 0 else "%d FPS" % f)
	disp_fps_opt = _mk_opt(flabels, func(i: int):
		fps_cap = FPS_CAPS[i]
		_prefs_set("fps_cap", fps_cap)
		_apply_display())
	dc3.add_child(disp_fps_opt)
	var dc4 := VBoxContainer.new()
	dc4.add_child(UIKit.label("FPS EN ARRIÈRE-PLAN", 11, UIKit.COL_MUTED, true))
	var blabels: Array = []
	for f in FPS_BG:
		blabels.append("COMME ACTIF" if f == 0 else "%d FPS" % f)
	disp_fpsbg_opt = _mk_opt(blabels, func(i: int):
		fps_bg = FPS_BG[i]
		_prefs_set("fps_bg", fps_bg))
	dc4.add_child(disp_fpsbg_opt)
	for dc in [dc1, dc2, dc3, dc4]:
		dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drow.add_child(dc)
	v.add_child(drow)

	# ---- touches de tir ----
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("TOUCHES DE TIR", 11, UIKit.COL_MUTED, true))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 14)
	fire_btns = []
	for slot in 2:
		var fb := UIKit.btn("", false, 13)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.pressed.connect(func():
			fire_wait = slot
			fire_btns[slot].text = "APPUIE SUR UNE TOUCHE… (Échap : annuler)")
		fire_btns.append(fb)
		frow.add_child(fb)
	v.add_child(frow)
	v.add_child(UIKit.label("Clique un bouton puis appuie sur la touche ou le bouton souris voulu. Clic gauche par défaut ; les deux touches tirent.", 12, UIKit.COL_MUTED))

	# ---- son & qualité ----
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("SON & QUALITÉ", 11, UIKit.COL_MUTED, true))
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 14)
	var qc1 := VBoxContainer.new()
	qc1.add_child(UIKit.label("VOLUME", 11, UIKit.COL_MUTED, true))
	vol_slider = HSlider.new()
	vol_slider.min_value = 0
	vol_slider.max_value = 100
	vol_slider.step = 5
	vol_slider.custom_minimum_size = Vector2(0, 31)
	vol_slider.value_changed.connect(func(val: float):
		_prefs_set("vol", val)
		_apply_volume(val))
	qc1.add_child(vol_slider)
	var qc2 := VBoxContainer.new()
	qc2.add_child(UIKit.label("V-SYNC", 11, UIKit.COL_MUTED, true))
	vsync_opt = _mk_opt(["DÉSACTIVÉ", "ACTIVÉ"], func(i: int):
		_prefs_set("vsync", i)
		_apply_quality())
	qc2.add_child(vsync_opt)
	var qc3 := VBoxContainer.new()
	qc3.add_child(UIKit.label("ANTI-ALIASING", 11, UIKit.COL_MUTED, true))
	msaa_opt = _mk_opt(["DÉSACTIVÉ", "MSAA 2×", "MSAA 4×"], func(i: int):
		_prefs_set("msaa", i)
		_apply_quality())
	qc3.add_child(msaa_opt)
	var qc4 := VBoxContainer.new()
	qc4.add_child(UIKit.label("RENDU 3D", 11, UIKit.COL_MUTED, true))
	rscale_opt = _mk_opt(["100 %", "83 %", "67 %", "50 %"], func(i: int):
		_prefs_set("rscale", i)
		_apply_quality())
	qc4.add_child(rscale_opt)
	for qc in [qc1, qc2, qc3, qc4]:
		qc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qrow.add_child(qc)
	v.add_child(qrow)

	# ---- son de tir personnalisé ----
	var snrow := HBoxContainer.new()
	snrow.add_theme_constant_override("separation", 10)
	var pick := UIKit.btn("CHOISIR UN FICHIER…", false, 12)
	pick.pressed.connect(_pick_hit_sound)
	snrow.add_child(pick)
	var rst := UIKit.btn("SON PAR DÉFAUT", false, 12)
	rst.pressed.connect(_reset_hit_sound)
	snrow.add_child(rst)
	custom_snd_lbl = UIKit.label("", 12, UIKit.COL_ACCENT2, true)
	custom_snd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_snd_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	snrow.add_child(custom_snd_lbl)
	v.add_child(snrow)
	v.add_child(UIKit.label("Son joué à chaque cible touchée. Formats audio : .mp3, .ogg, .wav (le .mp4 est une vidéo, non pris en charge — convertis-le en .mp3).", 12, UIKit.COL_MUTED))

	# ---- viseur (éditeur type Valorant) ----
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("VISEUR", 11, UIKit.COL_MUTED, true))
	var xbody := HBoxContainer.new()
	xbody.add_theme_constant_override("separation", 18)
	var xcol := VBoxContainer.new()
	xcol.add_theme_constant_override("separation", 9)
	xcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 14)
	var tc1 := VBoxContainer.new()
	tc1.add_child(UIKit.label("COULEUR", 11, UIKit.COL_MUTED, true))
	ch_col_pick = _mk_color_pick(str(_prefs_get("ch_col_hex", "E9EEF6")), func(c: Color):
		_prefs_set("ch_col_hex", c.to_html(false))
		_apply_crosshair())
	tc1.add_child(ch_col_pick)
	var tc2 := VBoxContainer.new()
	tc2.add_child(UIKit.label("LIGNES", 11, UIKit.COL_MUTED, true))
	var lines_opt := _mk_opt(["SANS", "AVEC"], func(i: int):
		_prefs_set("ch_lines", i)
		_apply_crosshair())
	lines_opt.select(clampi(int(_prefs_get("ch_lines", 1)), 0, 1))
	tc2.add_child(lines_opt)
	var tc3 := VBoxContainer.new()
	tc3.add_child(UIKit.label("POINT CENTRAL", 11, UIKit.COL_MUTED, true))
	var dot_opt := _mk_opt(["SANS", "AVEC"], func(i: int):
		_prefs_set("ch_dot", i)
		_apply_crosshair())
	dot_opt.select(clampi(int(_prefs_get("ch_dot", 0)), 0, 1))
	tc3.add_child(dot_opt)
	var tc4 := VBoxContainer.new()
	tc4.add_child(UIKit.label("CONTOUR", 11, UIKit.COL_MUTED, true))
	var out_opt := _mk_opt(["SANS", "AVEC"], func(i: int):
		_prefs_set("ch_outline", i)
		_apply_crosshair())
	out_opt.select(clampi(int(_prefs_get("ch_outline", 0)), 0, 1))
	tc4.add_child(out_opt)
	var tc5 := VBoxContainer.new()
	tc5.add_child(UIKit.label("FLASH AU TIR RÉUSSI", 11, UIKit.COL_MUTED, true))
	var flash_opt := _mk_opt(["SANS", "AVEC"], func(i: int):
		_prefs_set("ch_flash", i)
		_apply_crosshair())
	flash_opt.select(clampi(int(_prefs_get("ch_flash", 1)), 0, 1))
	tc5.add_child(flash_opt)
	for tc in [tc1, tc2, tc3, tc4, tc5]:
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(tc)
	xcol.add_child(trow)
	xcol.add_child(_ch_slider("LONGUEUR DES LIGNES", "ch_len", 0.0, 30.0, 1.0, 7.0))
	xcol.add_child(_ch_slider("ÉPAISSEUR DES LIGNES", "ch_thick", 1.0, 8.0, 0.5, 2.0))
	xcol.add_child(_ch_slider("ÉCART AU CENTRE", "ch_gap", 0.0, 30.0, 1.0, 4.0))
	xcol.add_child(_ch_slider("TAILLE DU POINT", "ch_dot_size", 1.0, 12.0, 0.5, 2.0))
	xbody.add_child(xcol)
	var prev_col := VBoxContainer.new()
	prev_col.add_theme_constant_override("separation", 4)
	prev_col.add_child(UIKit.label("APERÇU", 11, UIKit.COL_MUTED, true))
	var prev_pc := PanelContainer.new()
	prev_pc.add_theme_stylebox_override("panel", UIKit.panel_style(Color("0B0F17"), UIKit.COL_LINE, 8, 0))
	prev_pc.custom_minimum_size = Vector2(150, 150)
	prev_pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch_preview = CrossDraw.new()
	ch_preview.preview = true
	ch_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev_pc.add_child(ch_preview)
	prev_col.add_child(prev_pc)
	xbody.add_child(prev_col)
	v.add_child(xbody)

	# ---- monde & effets ----
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("MONDE & EFFETS", 11, UIKit.COL_MUTED, true))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	var wc0 := VBoxContainer.new()
	wc0.add_child(UIKit.label("CARRÉS DU FOND", 11, UIKit.COL_MUTED, true))
	grid_base_pick = _mk_color_pick(str(_prefs_get("grid_base_hex", "0B0F15")), func(c: Color):
		_prefs_set("grid_base_hex", c.to_html(false))
		_apply_grid())
	wc0.add_child(grid_base_pick)
	var wc1 := VBoxContainer.new()
	wc1.add_child(UIKit.label("LIGNES DU FOND", 11, UIKit.COL_MUTED, true))
	grid_line_pick = _mk_color_pick(str(_prefs_get("grid_line_hex", "1A475C")), func(c: Color):
		_prefs_set("grid_line_hex", c.to_html(false))
		_apply_grid())
	wc1.add_child(grid_line_pick)
	var wc2 := VBoxContainer.new()
	wc2.add_child(UIKit.label("CIEL / FOND", 11, UIKit.COL_MUTED, true))
	bg_col_pick = _mk_color_pick(str(_prefs_get("bg_hex", "0B0F17")), func(c: Color):
		_prefs_set("bg_hex", c.to_html(false))
		_apply_bg())
	wc2.add_child(bg_col_pick)
	var wc3 := VBoxContainer.new()
	wc3.add_child(UIKit.label("ANIMATION DE DISPARITION", 11, UIKit.COL_MUTED, true))
	pop_opt = _mk_opt(["NET (SANS)", "ANIMÉE"], func(i: int):
		_prefs_set("pop_fx", i)
		_apply_fx())
	wc3.add_child(pop_opt)
	var wc4 := VBoxContainer.new()
	wc4.add_child(UIKit.label("GLOW DES SPHÈRES", 11, UIKit.COL_MUTED, true))
	glow_opt = _mk_opt(["SANS", "AVEC"], func(i: int):
		_prefs_set("glow", i)
		_apply_glow())
	wc4.add_child(glow_opt)
	for wc in [wc0, wc1, wc2, wc3, wc4]:
		wc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrow.add_child(wc)
	v.add_child(wrow)

	# l'onglet est devenu long : zone scrollable
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	return sc

func _apply_volume(val: float) -> void:
	AudioServer.set_bus_mute(0, val <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(val / 100.0, 0.001)))

func _apply_quality() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if int(_prefs_get("vsync", 0)) == 1 else DisplayServer.VSYNC_DISABLED)
	get_viewport().msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][
		clampi(int(_prefs_get("msaa", 2)), 0, 2)]
	get_viewport().scaling_3d_scale = RSCALES[clampi(int(_prefs_get("rscale", 0)), 0, RSCALES.size() - 1)]

func _apply_crosshair() -> void:
	_ch_apply(crosshair)
	if ch_preview != null:
		_ch_apply(ch_preview)

func _ch_apply(cd: CrossDraw) -> void:
	cd.ch_col = Color(str(_prefs_get("ch_col_hex", "E9EEF6")))
	cd.ch_dot = int(_prefs_get("ch_dot", 0)) == 1
	cd.ch_dot_size = float(_prefs_get("ch_dot_size", 2.0))
	cd.ch_lines = int(_prefs_get("ch_lines", 1)) == 1
	cd.ch_len = float(_prefs_get("ch_len", 7.0))
	cd.ch_thick = float(_prefs_get("ch_thick", 2.0))
	cd.ch_gap = float(_prefs_get("ch_gap", 4.0))
	cd.ch_outline = int(_prefs_get("ch_outline", 0)) == 1
	cd.ch_flash = int(_prefs_get("ch_flash", 1)) == 1
	cd.queue_redraw()

# couleur du ciel/fond derrière la grille (fond + teinte du brouillard)
func _apply_bg() -> void:
	var c := Color(str(_prefs_get("bg_hex", "0B0F17")))
	world_env.background_color = c
	world_env.fog_light_color = c

# couleur des carrés et des lignes de la grille (sol + murs)
func _apply_grid() -> void:
	var base := Color(str(_prefs_get("grid_base_hex", "0B0F15")))
	var line := Color(str(_prefs_get("grid_line_hex", "1A475C")))
	for mat in grid_mats:
		mat.set_shader_parameter("grid_base", Vector3(base.r, base.g, base.b))
		mat.set_shader_parameter("grid_line", Vector3(line.r, line.g, line.b))

# animation de disparition des cibles (net par défaut)
func _apply_fx() -> void:
	pop_enabled = int(_prefs_get("pop_fx", 0)) == 1

# effet de glow (bloom) sur les sphères
func _apply_glow() -> void:
	world_env.glow_enabled = int(_prefs_get("glow", 1)) == 1

# ---- son de tir personnalisé ----
func _pick_hit_sound() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		if custom_snd_lbl != null:
			custom_snd_lbl.text = "sélecteur de fichier indisponible sur ce système"
		return
	DisplayServer.file_dialog_show(
		"Choisir un son de tir (.mp3, .ogg, .wav)", OS.get_system_dir(OS.SYSTEM_DIR_MUSIC), "",
		false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.mp3,*.ogg,*.wav ; Fichiers audio"]),
		_on_hit_sound_picked)

func _on_hit_sound_picked(status: bool, paths: PackedStringArray, _idx: int) -> void:
	if not status or paths.is_empty():
		return
	var src := paths[0]
	var ext := src.get_extension().to_lower()
	if ["mp3", "ogg", "wav"].find(ext) < 0:
		custom_snd_lbl.text = "⚠ format non pris en charge (utilise .mp3, .ogg ou .wav)"
		return
	var bytes := FileAccess.get_file_as_bytes(src)
	if bytes.is_empty():
		custom_snd_lbl.text = "⚠ lecture du fichier impossible"
		return
	var dst := "user://hitsound." + ext
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		custom_snd_lbl.text = "⚠ copie du fichier impossible"
		return
	f.store_buffer(bytes)
	f.close()
	if _load_hit_sound(dst):
		_prefs_set("hit_sound", dst)
		custom_snd_lbl.text = "son perso : %s" % src.get_file()
	else:
		custom_snd_lbl.text = "⚠ audio illisible — son par défaut conservé"

# construit un AudioStream selon l'extension ; renvoie true si ok
func _load_hit_sound(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var ext := path.get_extension().to_lower()
	var s: AudioStream = null
	if ext == "mp3":
		var m := AudioStreamMP3.new()
		m.data = FileAccess.get_file_as_bytes(path)
		s = m
	elif ext == "ogg":
		s = AudioStreamOggVorbis.load_from_file(path)
	elif ext == "wav":
		s = AudioStreamWAV.load_from_file(path)
	if s == null:
		return false
	snd_hit.stream = s
	return true

func _reset_hit_sound() -> void:
	snd_hit.stream = snd_hit_default
	_cfg_ref().set_value("prefs", "hit_sound", "")
	_cfg_ref().save("user://senslab.cfg")
	if custom_snd_lbl != null:
		custom_snd_lbl.text = "son par défaut"

func _mk_opt(items: Array, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_override("font", UIKit.mono())
	o.add_theme_font_size_override("font_size", 13)
	for it in items:
		o.add_item(str(it))
	o.item_selected.connect(cb)
	return o

func _mk_color_pick(hex: String, cb: Callable) -> ColorPickerButton:
	var cpb := ColorPickerButton.new()
	cpb.focus_mode = Control.FOCUS_NONE
	cpb.custom_minimum_size = Vector2(0, 31)
	cpb.edit_alpha = false
	cpb.color = Color(hex)
	cpb.add_theme_font_override("font", UIKit.mono())
	cpb.add_theme_font_size_override("font_size", 12)
	cpb.color_changed.connect(cb)
	return cpb

# ligne de réglage viseur : label + slider (px) + valeur, sauvegarde live
func _ch_slider(label: String, key: String, minv: float, maxv: float, step: float, def: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lab := UIKit.label(label, 11, UIKit.COL_MUTED, true)
	lab.custom_minimum_size = Vector2(180, 0)
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = minv
	sl.max_value = maxv
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(0, 24)
	sl.focus_mode = Control.FOCUS_NONE
	sl.set_value_no_signal(float(_prefs_get(key, def)))
	var vl := UIKit.label(("%.1f px" % float(_prefs_get(key, def))).replace(".0 ", " "), 12, UIKit.COL_TEXT, true)
	vl.custom_minimum_size = Vector2(56, 0)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(val: float):
		vl.text = ("%.1f px" % val).replace(".0 ", " ")
		_prefs_set(key, val)
		_apply_crosshair())
	row.add_child(sl)
	row.add_child(vl)
	return row

# ---- affichage : applique fenêtre / écran / fps depuis les prefs ----
func _apply_display() -> void:
	var w := get_window()
	var scr: int = clampi(int(_prefs_get("screen", 0)), 0, DisplayServer.get_screen_count() - 1)
	var mi: int = clampi(int(_prefs_get("win_mode", 0)), 0, WIN_MODES.size() - 1)
	var m: Dictionary = WIN_MODES[mi]
	if m.get("fs", false):
		w.current_screen = scr
		w.mode = Window.MODE_FULLSCREEN
	else:
		w.mode = Window.MODE_WINDOWED
		w.current_screen = scr
		w.size = Vector2i(int(m["w"]), int(m["h"]))
		var r := DisplayServer.screen_get_usable_rect(scr)
		w.position = r.position + (r.size - Vector2i(w.size)) / 2
	Engine.max_fps = fps_cap
	_apply_camera_fov()

# ---- touches de tir ----
func _bind_name(b: String) -> String:
	if b == "":
		return "—"
	var p := b.split(":")
	if p[0] == "mouse":
		match int(p[1]):
			1: return "CLIC GAUCHE"
			2: return "CLIC DROIT"
			3: return "CLIC MOLETTE"
			8: return "SOURIS X1"
			9: return "SOURIS X2"
			_: return "SOURIS %s" % p[1]
	return OS.get_keycode_string(int(p[1]))

func _refresh_fire_btns() -> void:
	for i in 2:
		fire_btns[i].text = "TIR %d : %s" % [i + 1, _bind_name(fire_binds[i])]

func _event_bind(event: InputEvent) -> String:
	if event is InputEventMouseButton and event.pressed:
		return "mouse:%d" % event.button_index
	if event is InputEventKey and event.pressed and not event.echo:
		return "key:%d" % event.keycode
	return ""

func _capture_fire_bind(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		fire_wait = -1
		_refresh_fire_btns()
		get_viewport().set_input_as_handled()
		return
	var eb := _event_bind(event)
	if eb == "":
		return
	# une même touche ne peut pas occuper les deux slots
	var other := 1 - fire_wait
	if fire_binds[other] == eb:
		fire_binds[other] = ""
	fire_binds[fire_wait] = eb
	_prefs_set("fire1", fire_binds[0])
	_prefs_set("fire2", fire_binds[1])
	fire_wait = -1
	_refresh_fire_btns()
	get_viewport().set_input_as_handled()

func _build_count() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cnt_round_lbl = UIKit.label("", 14, UIKit.COL_ACCENT, true)
	cnt_round_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt_num_lbl = UIKit.label("3", 90, UIKit.COL_TEXT, true)
	cnt_num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt_score_lbl = UIKit.label("", 15, UIKit.COL_MUTED, true)
	cnt_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cnt_round_lbl)
	v.add_child(cnt_num_lbl)
	v.add_child(cnt_score_lbl)
	count_panel = UIKit.overlay_wrap(v, 0.35)
	ui.add_child(count_panel)

func _build_quit() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(360, 0)
	vb.add_child(UIKit.label("QUITTER", 12, UIKit.COL_ACCENT, true))
	vb.add_child(UIKit.label("Quitter SensLab ?", 16, UIKit.COL_TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var yes := UIKit.btn("QUITTER", true, 13)
	yes.pressed.connect(func(): get_tree().quit())
	var no := UIKit.btn("ANNULER", false, 13)
	no.pressed.connect(func(): quit_panel.visible = false)
	for b in [yes, no]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	vb.add_child(row)
	card.add_child(vb)
	quit_panel = UIKit.overlay_wrap(card)
	quit_panel.visible = false
	ui.add_child(quit_panel)

func _build_pause() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIKit.label("PAUSE", 12, UIKit.COL_ACCENT, true))
	v.add_child(UIKit.label("Le chrono est figé.", 15, UIKit.COL_TEXT))
	var b := UIKit.btn("REPRENDRE", true)
	b.pressed.connect(_resume)
	v.add_child(b)
	pause_restart_btn = UIKit.btn("RECOMMENCER", false)
	pause_restart_btn.pressed.connect(_restart_run)
	v.add_child(pause_restart_btn)
	var m := UIKit.btn("RETOUR AU MENU", false)
	m.pressed.connect(_goto_menu)
	v.add_child(m)
	var q := UIKit.btn("QUITTER SENS LAB", false)
	q.pressed.connect(func(): get_tree().quit())
	v.add_child(q)
	card.add_child(v)
	pause_panel = UIKit.overlay_wrap(card)
	ui.add_child(pause_panel)

func _build_fres() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 12, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(820, 0)
	card.add_child(v)

	v.add_child(UIKit.label("◈ VERDICT DE CALIBRATION", 12, UIKit.COL_ACCENT, true))

	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 40)
	var main := VBoxContainer.new()
	res_game_lbl = UIKit.label("", 11, UIKit.COL_MUTED, true)
	res_sens_lbl = UIKit.label("", 52, UIKit.COL_TEXT, true)
	res_range_lbl = UIKit.label("", 13, UIKit.COL_ACCENT, true)
	res_conf_lbl = UIKit.label("", 12, UIKit.COL_ACCENT2, true)
	for n in [res_game_lbl, res_sens_lbl, res_range_lbl, res_conf_lbl]:
		main.add_child(n)
	res_equiv_box = VBoxContainer.new()
	res_equiv_box.add_theme_constant_override("separation", 3)
	hero.add_child(main)
	hero.add_child(res_equiv_box)
	v.add_child(hero)

	curve_ctl = CurveDraw.new()
	curve_ctl.custom_minimum_size = Vector2(800, 170)
	v.add_child(curve_ctl)

	res_table = GridContainer.new()
	res_table.columns = 8
	res_table.add_theme_constant_override("h_separation", 16)
	res_table.add_theme_constant_override("v_separation", 2)
	v.add_child(res_table)

	res_diag = RichTextLabel.new()
	res_diag.bbcode_enabled = true
	res_diag.fit_content = true
	res_diag.add_theme_font_size_override("normal_font_size", 12)
	res_diag.add_theme_color_override("default_color", UIKit.COL_MUTED)
	res_diag.custom_minimum_size = Vector2(800, 0)
	v.add_child(res_diag)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var b1 := UIKit.btn("ESSAYER CETTE SENS", true, 13)
	b1.pressed.connect(_start_sandbox)
	var b2 := UIKit.btn("REFAIRE", false, 13)
	b2.pressed.connect(func(): _start_finder(protocol))
	var b3 := UIKit.btn("MENU", false, 13)
	b3.pressed.connect(_goto_menu)
	for b in [b1, b2, b3]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	v.add_child(actions)

	fres_panel = UIKit.overlay_wrap(card)
	ui.add_child(fres_panel)

func _build_tres() -> void:
	# dashboard : le replay première personne joue derrière, panneaux sur les côtés
	tres_panel = Control.new()
	tres_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.032, 0.052, 0.24)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tres_panel.add_child(dim)
	rp_overlay = ReplayOverlay.new(self)
	tres_panel.add_child(rp_overlay)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for mrg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(mrg, 32)
	mc.mouse_filter = Control.MOUSE_FILTER_PASS
	tres_panel.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	mc.add_child(v)

	# ---- corps : score à gauche, diagnostics/classement à droite, centre libre ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(left)
	var head_pc := PanelContainer.new()
	head_pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 18))
	left.add_child(head_pc)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	head_pc.add_child(hv)
	tres_title = UIKit.label("", 14, UIKit.COL_ACCENT, true)
	tres_score = UIKit.label("", 46, UIKit.COL_TEXT, true)
	tres_record = UIKit.label("", 12, UIKit.COL_ACCENT2, true)
	hv.add_child(tres_title)
	hv.add_child(tres_score)
	hv.add_child(tres_record)
	dash_chips_box = GridContainer.new()
	dash_chips_box.columns = 3
	dash_chips_box.add_theme_constant_override("h_separation", 8)
	dash_chips_box.add_theme_constant_override("v_separation", 8)
	hv.add_child(dash_chips_box)
	tres_net = UIKit.label("", 11, UIKit.COL_MUTED, true)
	hv.add_child(tres_net)

	var csp := Control.new()
	csp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(csp)

	var right_pc := PanelContainer.new()
	right_pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 16))
	right_pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(right_pc)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 9)
	right.custom_minimum_size = Vector2(440, 0)
	right_pc.add_child(right)
	right.add_child(UIKit.label("CE QU'IL FAUT AMÉLIORER", 12, UIKit.COL_ACCENT, true))
	dash_diag = RichTextLabel.new()
	dash_diag.bbcode_enabled = true
	dash_diag.fit_content = true
	dash_diag.add_theme_font_size_override("normal_font_size", 12)
	dash_diag.add_theme_color_override("default_color", UIKit.COL_MUTED)
	dash_diag.custom_minimum_size = Vector2(440, 0)
	right.add_child(dash_diag)
	right.add_child(HSeparator.new())
	right.add_child(UIKit.label("CLASSEMENT — CET EXERCICE", 12, UIKit.COL_ACCENT, true))
	dash_lb_status = UIKit.label("", 11, UIKit.COL_MUTED, true)
	right.add_child(dash_lb_status)
	dash_lb_grid = GridContainer.new()
	dash_lb_grid.columns = 3
	dash_lb_grid.add_theme_constant_override("h_separation", 24)
	dash_lb_grid.add_theme_constant_override("v_separation", 2)
	right.add_child(dash_lb_grid)
	right.add_child(HSeparator.new())
	right.add_child(UIKit.label("ENCHAÎNER UN AUTRE EXERCICE", 12, UIKit.COL_ACCENT, true))
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", 10)
	dash_mode_opt = OptionButton.new()
	dash_mode_opt.focus_mode = Control.FOCUS_NONE
	dash_mode_opt.add_theme_font_override("font", UIKit.mono())
	dash_mode_opt.add_theme_font_size_override("font_size", 13)
	dash_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pack_labels := {}
	for pack in PACKS:
		pack_labels[pack["key"]] = pack["label"]
	for i in MODE_ORDER.size():
		var m: Dictionary = MODES[MODE_ORDER[i]]
		dash_mode_opt.add_item("%s · %s ◆%d" % [pack_labels[m["pack"]], m["name"], m["diff"]], i)
	chain.add_child(dash_mode_opt)
	var go := UIKit.btn("LANCER", true, 13)
	go.pressed.connect(func(): _open_setup(MODE_ORDER[dash_mode_opt.selected], true))
	chain.add_child(go)
	right.add_child(chain)
	tres_pl_row = HBoxContainer.new()
	tres_pl_row.add_theme_constant_override("separation", 10)
	tres_pl_row.visible = false
	tres_pl_lbl = UIKit.label("", 12, UIKit.COL_ACCENT2, true)
	tres_pl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tres_pl_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tres_pl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tres_pl_row.add_child(tres_pl_lbl)
	tres_pl_next = UIKit.btn("EXERCICE SUIVANT ▶", true, 13)
	tres_pl_next.pressed.connect(_pl_next)
	tres_pl_row.add_child(tres_pl_next)
	var plstop := UIKit.btn("ARRÊTER", false, 12)
	plstop.pressed.connect(_pl_stop)
	tres_pl_row.add_child(plstop)
	right.add_child(tres_pl_row)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var b1 := UIKit.btn("REJOUER", true, 13)
	b1.pressed.connect(func(): _start_train(t_mode))
	var b2 := UIKit.btn("MENU", false, 13)
	b2.pressed.connect(_goto_menu)
	for b in [b1, b2]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	right.add_child(actions)

	# ---- barre du bas : contrôles du replay ----
	var bot_pc := PanelContainer.new()
	bot_pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 12))
	v.add_child(bot_pc)
	var rctl := HBoxContainer.new()
	rctl.add_theme_constant_override("separation", 10)
	bot_pc.add_child(rctl)
	rctl.add_child(UIKit.label("REPLAY", 12, UIKit.COL_ACCENT, true))
	rp_play_btn = UIKit.btn("⏸ PAUSE", false, 12)
	rp_play_btn.pressed.connect(func():
		rp_playing = not rp_playing
		rp_play_btn.text = "⏸ PAUSE" if rp_playing else "▶ LECTURE")
	rctl.add_child(rp_play_btn)
	rp_speed_btns = []
	for sp in [0.5, 1.0, 2.0]:
		var sb := UIKit.btn(("×%.1f" % sp).replace(".0", ""), false, 12)
		sb.pressed.connect(func():
			rp_speed = sp
			for i in rp_speed_btns.size():
				UIKit.set_btn_selected(rp_speed_btns[i], rp_speed_btns[i] == sb))
		rp_speed_btns.append(sb)
		rctl.add_child(sb)
	rp_time_ctl = TimelineDraw.new()
	rp_time_ctl.custom_minimum_size = Vector2(300, 34)
	rp_time_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rp_time_ctl.on_seek = _rp_seek
	rctl.add_child(rp_time_ctl)
	var leg2 := RichTextLabel.new()
	leg2.bbcode_enabled = true
	leg2.fit_content = true
	leg2.custom_minimum_size = Vector2(430, 0)
	leg2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leg2.add_theme_font_size_override("normal_font_size", 11)
	leg2.text = "[color=#7CE38B]— sur la cible[/color]  [color=#FFB454]— dépassement[/color]  [color=#57D4FF]— trajet[/color]  [color=#FF4655]✕ raté[/color]  [color=#FFB454]✕ trop tôt[/color]"
	rctl.add_child(leg2)
	ui.add_child(tres_panel)

# ============================================================
#  PRÉ-LANCEMENT — paramétrage du mode
#  Paramètres par défaut = score classé ; modifiés = run libre
#  (ni record ni classement, comme les modes custom d'Aimlabs).
# ============================================================
func _build_setup() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 12, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(660, 0)
	card.add_child(v)
	setup_title = UIKit.label("", 20, UIKit.COL_TEXT, true)
	v.add_child(setup_title)
	setup_desc = UIKit.label("", 12, UIKit.COL_MUTED)
	setup_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(setup_desc)
	var drow := HBoxContainer.new()
	setup_dur_row = drow
	drow.add_theme_constant_override("separation", 8)
	drow.add_child(UIKit.label("DURÉE", 11, UIKit.COL_MUTED, true))
	setup_dur_btns = []
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 12)
		db.pressed.connect(func():
			_set_duration(d)
			_setup_sync_dur())
		setup_dur_btns.append(db)
		drow.add_child(db)
	v.add_child(drow)
	v.add_child(HSeparator.new())
	setup_rows = VBoxContainer.new()
	setup_rows.add_theme_constant_override("separation", 6)
	v.add_child(setup_rows)
	setup_status = UIKit.label("", 12, UIKit.COL_OK, true)
	v.add_child(setup_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var b1 := UIKit.btn("LANCER", true, 14)
	setup_launch_btn = b1
	b1.pressed.connect(_setup_launch)
	var b2 := UIKit.btn("PAR DÉFAUT", false, 13)
	b2.pressed.connect(_setup_reset)
	var b3 := UIKit.btn("RETOUR", false, 13)
	b3.pressed.connect(_setup_back)
	for b in [b1, b2, b3]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	v.add_child(actions)
	setup_panel = UIKit.overlay_wrap(card)
	ui.add_child(setup_panel)

# paramètres réglables selon le type du mode (def = valeur du mode)
func _setup_specs(mk: String) -> Array:
	var m: Dictionary = MODES[mk]
	if m["type"] == "click":
		return [
			{"key": "r", "label": "TAILLE DES CIBLES", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
			{"key": "cone", "label": "ÉCART MAX ENTRE CIBLES", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
			{"key": "simul", "label": "CIBLES SIMULTANÉES", "min": 1, "max": 6, "step": 1, "def": float(m.get("simul", 1)), "fmt": "int"},
			{"key": "ttl", "label": "DURÉE DE VIE DES CIBLES", "min": 0.0, "max": 3.0, "step": 0.1, "def": float(m.get("ttl", 0.0)), "fmt": "sec"},
			{"key": "move", "label": "VITESSE DES CIBLES", "min": 0.0, "max": 60.0, "step": 2.0, "def": float(m.get("move", 0.0)), "fmt": "degs"},
		]
	return [
		{"key": "r", "label": "TAILLE DE LA CIBLE", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
		{"key": "v", "label": "VITESSE DE LA CIBLE", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
		{"key": "band", "label": "LARGEUR DE LA ZONE", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
		{"key": "amp", "label": "AMPLITUDE VERTICALE", "min": 0.5, "max": 2.0, "step": 0.05, "def": 1.0, "fmt": "mult"},
	]

func _fmt_param(spec: Dictionary, v: float) -> String:
	match str(spec["fmt"]):
		"int": return str(int(v))
		"sec": return "∞" if v <= 0.0 else "%.1f s" % v
		"degs": return "immobile" if v <= 0.0 else "%d °/s" % int(v)
	return "×%.2f" % v

func _open_setup(mk: String, from_dash: bool = false, ctx: String = "play", preset: Dictionary = {}) -> void:
	setup_mode = mk
	setup_from_dash = from_dash
	setup_ctx = ctx
	setup_launch_btn.text = "ENREGISTRER L'EXERCICE" if ctx == "playlist" else "LANCER"
	setup_dur_row.visible = ctx != "playlist"     # en playlist la durée est réglée par la playlist
	var m: Dictionary = MODES[mk]
	setup_title.text = "%s  %s" % [m["name"], "◆".repeat(int(m["diff"]))]
	setup_desc.text = str(m["desc"])
	_setup_sync_dur()
	for ch in setup_rows.get_children():
		ch.queue_free()
	setup_sliders = []
	var saved: Dictionary = preset if ctx == "playlist" else _cfg_ref().get_value("custom", mk, {})
	for spec in _setup_specs(mk):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var lab := UIKit.label(spec["label"], 12, UIKit.COL_MUTED, true)
		lab.custom_minimum_size = Vector2(260, 0)
		row.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = spec["min"]
		sl.max_value = spec["max"]
		sl.step = spec["step"]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.custom_minimum_size = Vector2(0, 26)
		sl.focus_mode = Control.FOCUS_NONE
		sl.set_value_no_signal(float(saved.get(spec["key"], spec["def"])))
		var vl := UIKit.label("", 13, UIKit.COL_TEXT, true)
		vl.custom_minimum_size = Vector2(90, 0)
		row.add_child(sl)
		row.add_child(vl)
		setup_rows.add_child(row)
		setup_sliders.append({"spec": spec, "slider": sl, "lbl": vl})
		vl.text = _fmt_param(spec, sl.value)
		sl.value_changed.connect(func(val: float):
			vl.text = _fmt_param(spec, val)
			_setup_refresh_status())
	_setup_refresh_status()
	_show_only(setup_panel)

# overrides ≠ défauts uniquement (vide = run classé)
func _setup_custom() -> Dictionary:
	var c := {}
	for e in setup_sliders:
		var spec: Dictionary = e["spec"]
		var val: float = e["slider"].value
		if absf(val - float(spec["def"])) > 0.001:
			c[spec["key"]] = val
	return c

func _setup_refresh_status() -> void:
	var is_def := _setup_custom().is_empty()
	if is_def:
		setup_status.text = "PARAMÈTRES PAR DÉFAUT — %s" % ("cet exercice restera classé" if setup_ctx == "playlist" else "record et classement actifs")
		setup_status.add_theme_color_override("font_color", UIKit.COL_OK)
	else:
		setup_status.text = "PERSONNALISÉ — %s" % ("exercice non classé" if setup_ctx == "playlist" else "score non classé (ni record ni classement en ligne)")
		setup_status.add_theme_color_override("font_color", Color("FFB454"))

func _setup_sync_dur() -> void:
	for i in DURATIONS.size():
		UIKit.set_btn_selected(setup_dur_btns[i], DURATIONS[i] == t_dur)

func _setup_reset() -> void:
	for e in setup_sliders:
		e["slider"].set_value_no_signal(float(e["spec"]["def"]))
		e["lbl"].text = _fmt_param(e["spec"], float(e["slider"].value))
	_setup_refresh_status()

func _setup_back() -> void:
	if setup_ctx == "playlist":
		_show_only(pl_edit_panel)
	elif setup_from_dash and mode == Mode.T_RESULTS:
		_show_only(tres_panel)
	else:
		_show_only(menu_panel)

func _setup_launch() -> void:
	if setup_ctx == "playlist":
		if setup_item_idx >= 0 and setup_item_idx < pl_edit_items.size():
			pl_edit_items[setup_item_idx]["cust"] = _setup_custom()
		_pl_edit_render()
		_show_only(pl_edit_panel)
		return
	custom = _setup_custom()
	_cfg_ref().set_value("custom", setup_mode, custom)
	_cfg_ref().save("user://senslab.cfg")
	_start_train(setup_mode)

# config effective du run : MODES[mk] + overrides custom
func _train_cfg(mk: String, cust: Dictionary) -> Dictionary:
	var m: Dictionary = MODES[mk].duplicate(true)
	if cust.is_empty():
		return m
	if m["type"] == "click":
		m["r"] = float(m["r"]) * float(cust.get("r", 1.0))
		var cm := float(cust.get("cone", 1.0))
		m["cone"] = float(m["cone"]) * cm
		var pc := (float(m["p_lo"]) + float(m["p_hi"])) * 0.5
		var ph := (float(m["p_hi"]) - float(m["p_lo"])) * 0.5 * cm
		m["p_lo"] = pc - ph
		m["p_hi"] = pc + ph
		m["simul"] = int(cust.get("simul", m.get("simul", 1)))
		if m.has("grid_n"):
			# l'écart règle l'espacement de la grille = niveau de difficulté
			m["grid_step"] = float(m["grid_step"]) * cm
			m["simul"] = mini(int(m["simul"]), int(m["grid_n"]) * int(m["grid_n"]))
		var ttl := float(cust.get("ttl", m.get("ttl", 0.0)))
		if ttl > 0.0:
			m["ttl"] = ttl
		else:
			m.erase("ttl")
		var mv := float(cust.get("move", m.get("move", 0.0)))
		if mv > 0.0:
			m["move"] = mv
		else:
			m.erase("move")
	else:
		var trk: Dictionary = m["trk"]
		trk["r"] = float(trk["r"]) * float(cust.get("r", 1.0))
		if trk.has("v"):
			trk["v"] = float(trk["v"]) * float(cust.get("v", 1.0))
		if trk.has("spd"):
			trk["spd"] = float(trk["spd"]) * float(cust.get("v", 1.0))
		trk["band"] = float(trk["band"]) * float(cust.get("band", 1.0))
		trk["pitch_amp"] = float(trk["pitch_amp"]) * float(cust.get("amp", 1.0))
	return m

# ============================================================
#  VISIONNEUSE — replays des 5 meilleurs du classement
# ============================================================
func _build_rvw() -> void:
	rvw_panel = Control.new()
	rvw_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.032, 0.052, 0.18)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rvw_panel.add_child(dim)
	rvw_overlay = ReplayOverlay.new(self)
	rvw_panel.add_child(rvw_overlay)
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for mrg in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(mrg, 32)
	mc.mouse_filter = Control.MOUSE_FILTER_PASS
	rvw_panel.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	mc.add_child(v)
	var top_pc := PanelContainer.new()
	top_pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 12))
	top_pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(top_pc)
	rvw_title = UIKit.label("", 14, UIKit.COL_ACCENT2, true)
	top_pc.add_child(rvw_title)
	var spv := Control.new()
	spv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spv)
	var bot_pc := PanelContainer.new()
	bot_pc.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE, 10, 12))
	v.add_child(bot_pc)
	var rctl := HBoxContainer.new()
	rctl.add_theme_constant_override("separation", 10)
	bot_pc.add_child(rctl)
	rctl.add_child(UIKit.label("REPLAY", 12, UIKit.COL_ACCENT, true))
	rvw_play_btn = UIKit.btn("⏸ PAUSE", false, 12)
	rvw_play_btn.pressed.connect(func():
		rp_playing = not rp_playing
		rvw_play_btn.text = "⏸ PAUSE" if rp_playing else "▶ LECTURE")
	rctl.add_child(rvw_play_btn)
	rvw_speed_btns = []
	for sp in [0.5, 1.0, 2.0]:
		var sb := UIKit.btn(("×%.1f" % sp).replace(".0", ""), false, 12)
		sb.pressed.connect(func():
			rp_speed = sp
			for i in rvw_speed_btns.size():
				UIKit.set_btn_selected(rvw_speed_btns[i], rvw_speed_btns[i] == sb))
		rvw_speed_btns.append(sb)
		rctl.add_child(sb)
	rvw_time_ctl = TimelineDraw.new()
	rvw_time_ctl.custom_minimum_size = Vector2(300, 34)
	rvw_time_ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rvw_time_ctl.on_seek = _rp_seek
	rctl.add_child(rvw_time_ctl)
	var back := UIKit.btn("FERMER (ÉCHAP)", false, 12)
	back.pressed.connect(_rvw_close)
	rctl.add_child(back)
	ui.add_child(rvw_panel)

# une tuile de stat façon Aimlabs : titre + valeur
func _chip(title: String, value: String, col: Color) -> void:
	var pc := PanelContainer.new()
	var sb := UIKit.panel_style(UIKit.COL_GROUND, UIKit.COL_ACCENT2, 8, 10)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(146, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.add_child(UIKit.label(title, 10, UIKit.COL_MUTED, true))
	vb.add_child(UIKit.label(value, 19, col, true))
	pc.add_child(vb)
	dash_chips_box.add_child(pc)

func _show_only(panel: Control) -> void:
	for p in [menu_panel, count_panel, pause_panel, fres_panel, tres_panel, setup_panel, rvw_panel, pl_edit_panel]:
		p.visible = (p == panel)

# ============================================================
#  MENU — logique
# ============================================================
func _select_game(gk: String) -> void:
	_store_game_inputs()
	game = gk
	_load_game_inputs()
	_refresh_game_btns()
	_refresh_derived()

func _refresh_game_btns() -> void:
	for gk in game_btns:
		UIKit.set_btn_selected(game_btns[gk], gk == game)

func _store_game_inputs() -> void:
	_read_inputs()
	_prefs_set("sens_" + game, sens)
	_prefs_set("fov_" + game, fov_val)

func _load_game_inputs() -> void:
	var g := GameDB.get_game(game)
	in_sens.text = str(_prefs_get("sens_" + game, g["def"]))
	in_fov.text = str(_prefs_get("fov_" + game, g["fov_def"]))
	in_fov.editable = not g["fov_lock"]
	if g["fov_lock"]:
		in_fov.text = str(g["fov_def"])
	fov_hint_lbl.text = "fov %s : %s" % [g["label"].to_lower(), g["fov_hint"]]

func _read_inputs() -> void:
	var g := GameDB.get_game(game)
	sens = clamp(in_sens.text.replace(",", ".").to_float(), 0.001, 100.0)
	if sens <= 0.0:
		sens = g["def"]
	dpi = clamp(in_dpi.text.to_float(), 100.0, 26000.0)
	if dpi <= 0.0:
		dpi = 800.0
	fov_val = in_fov.text.replace(",", ".").to_float()
	if fov_val <= 0.0:
		fov_val = g["fov_def"]
	if g["fov_lock"]:
		fov_val = g["fov_def"]

func _refresh_derived() -> void:
	_read_inputs()
	derived_lbl.text = "eDPI %d · cm/360 %.1f cm · fov 16:9 %.0f°" % [
		int(sens * dpi), GameDB.cm360(game, sens, dpi), GameDB.hfov169(game, fov_val)]
	var who := pseudo if pseudo != "" else "sans pseudo"
	sum_lbl.text = "%s · %s · sens %s · %d dpi · edpi %d" % [
		who, GameDB.get_game(game)["label"], GameDB.fmt_sens(game, sens), int(dpi), int(sens * dpi)]

func _set_duration(d: int) -> void:
	t_dur = d
	for i in DURATIONS.size():
		UIKit.set_btn_selected(dur_btns[i], DURATIONS[i] == d)
	_refresh_mode_records()

func _refresh_mode_records() -> void:
	for mk in MODE_ORDER:
		var diff: int = MODES[mk]["diff"]
		var stars := "◆".repeat(diff) + "◇".repeat(5 - diff)
		var rec := _get_record(mk, t_dur)
		var rec_txt := ("record %d · %ds" % [rec, t_dur]) if rec > 0 else ("pas de record en %ds" % t_dur)
		mode_rec_lbls[mk].text = "%s   %s" % [stars, rec_txt]

func _refresh_last_calib() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://senslab.cfg") == OK:
		var last: Dictionary = cf.get_value("results", "last", {})
		if not last.is_empty():
			last_calib_lbl.text = "dernière calibration : %s %s (plage %s – %s)" % [
				last.get("label", ""), last.get("sens", ""), last.get("lo", ""), last.get("hi", "")]
			return
	last_calib_lbl.text = "aucune calibration enregistrée"

# ---- mise à jour auto ----
func _on_update_available(tag: String) -> void:
	upd_btn.text = "⬆ MISE À JOUR %s — INSTALLER" % tag
	upd_btn.visible = true
	upd_btn.disabled = false

func _on_check_updates() -> void:
	upd_manual = true
	upd_check_btn.disabled = true
	upd_check_btn.text = "VÉRIFICATION…"
	upd.check()

# feedback du bouton ; les checks automatiques restent silencieux (⬆ suffit)
func _on_upd_checked(ok: bool, newer: bool, tag: String) -> void:
	if not upd_manual:
		return
	upd_manual = false
	upd_check_btn.disabled = false
	if not ok:
		upd_check_btn.text = "⚠ VÉRIFICATION IMPOSSIBLE"
	elif newer:
		upd_check_btn.text = "MISE À JOUR %s TROUVÉE ⬆" % tag
	else:
		upd_check_btn.text = "✓ À JOUR (v%s)" % Updater.VERSION
	get_tree().create_timer(5.0).timeout.connect(func():
		upd_check_btn.text = "VÉRIFIER LES MISES À JOUR")

func _on_update_clicked() -> void:
	if not upd.can_install():
		OS.shell_open("https://github.com/%s/releases/latest" % Updater.REPO)
		return
	upd_btn.disabled = true
	upd_btn.text = "TÉLÉCHARGEMENT… 0%"
	upd.install()

func _on_update_progress(pct: int) -> void:
	upd_btn.text = "TÉLÉCHARGEMENT… %d%%" % pct
	if pct >= 100:
		upd_btn.text = "REDÉMARRAGE…"

func _on_update_failed(msg: String) -> void:
	upd_btn.disabled = false
	upd_btn.text = "⚠ %s — RÉESSAYER" % msg

func _goto_menu() -> void:
	mode = Mode.MENU
	paused = false
	pl_active = false                # quitter vers le menu interrompt la playlist
	trk_active = false
	_rp_clear()
	_clear_targets()
	hud_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_mode_records()
	_refresh_last_calib()
	_refresh_derived()
	_show_only(menu_panel)
	if room_code != "":
		_show_tab("duel")

# ============================================================
#  SENS FINDER — flow
# ============================================================
func _start_finder(pk: String) -> void:
	protocol = pk
	_read_inputs()
	_store_game_inputs()
	_save_prefs()
	_apply_camera_fov()
	var p: Dictionary = PROTOCOLS[pk]
	var base: Array = p["base"].duplicate()
	var first: float = base.pop_front()
	base.shuffle()
	plan = [{"k": first, "stage": "base"}]
	for kk in base:
		plan.append({"k": kk, "stage": "base"})
	rounds = []
	round_i = 0
	hud_root.visible = true
	_begin_round()

func _total_rounds() -> int:
	var p: Dictionary = PROTOCOLS[protocol]
	return p["base"].size() + p["refine"] + p["confirm"]

func _begin_round() -> void:
	k = plan[round_i]["k"]
	cur = {"k": k, "stage": plan[round_i]["stage"], "hits": 0, "misses": 0,
		"tth": [], "errs": [], "d0s": [], "ends": [], "sum_id": 0.0,
		"trk_on": 0.0, "trk_tot": 0.0}
	_clear_targets()
	trk_active = false
	var total := _total_rounds()
	var stage_txt := ""
	match plan[round_i]["stage"]:
		"refine": stage_txt = " · affinage"
		"confirm": stage_txt = " · confirmation"
	cnt_round_lbl.text = "ROUND %d / %d%s" % [round_i + 1, total, stage_txt.to_upper()]
	hud_l1.text = "round %d/%d%s" % [round_i + 1, total, stage_txt]
	if rounds.size() > 0:
		cnt_score_lbl.text = "score précédent  %d" % int(rounds[rounds.size() - 1]["score"])
	else:
		cnt_score_lbl.text = ""
	mode = Mode.COUNT
	count_ctx = "finder"
	count_timer = 2.4
	_show_only(count_panel)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _start_flick_phase() -> void:
	mode = Mode.F_FLICK
	paused = false
	phase_timer = PROTOCOLS[protocol]["flick"]
	hud_hint.text = "clique les cibles"
	anchor_yaw = yaw   # zone de jeu : le quart de map devant le joueur
	_refresh_finder_hud()
	_spawn_finder_target()

func _start_track_phase() -> void:
	mode = Mode.F_TRACK
	phase_timer = PROTOCOLS[protocol]["track"]
	hud_hint.text = "garde le viseur sur la cible"
	_clear_targets()
	_spawn_tracker(MODES["strafe"]["trk"])

# vrai pendant les premiers WARMUP_FRAC de la phase flick : le joueur s'adapte
# encore à la nouvelle sens (cf. NVIDIA CoG 2023), on n'enregistre pas ces essais
func _finder_warmup() -> bool:
	var flick_len: float = PROTOCOLS[protocol]["flick"]
	return (flick_len - phase_timer) < flick_len * WARMUP_FRAC

func _end_round() -> void:
	snd_round.play()
	trk_active = false
	_clear_targets()
	var p: Dictionary = PROTOCOLS[protocol]
	var acc := 0.0
	var tot: int = cur["hits"] + cur["misses"]
	if tot > 0:
		acc = float(cur["hits"]) / tot
	# throughput EFFECTIF ISO 9241-9 : IDe = log2(Ae/We + 1), We = 4,133·SD des
	# impacts (ratés inclus) — normalise le compromis vitesse/précision du joueur
	var tp := Analysis.tp_effective(cur["d0s"], cur["ends"], cur["tth"])
	var eff := tp >= 0.0
	if not eff:
		tp = cur["sum_id"] / float(p["flick"])   # fallback : ID nominal / durée
	var flick_norm: float = clamp(tp / (TP_REF_E if eff else TP_REF), 0.0, 1.6)
	var trk_pct := 0.0
	if cur["trk_tot"] > 0.0:
		trk_pct = cur["trk_on"] / cur["trk_tot"]
	var score := 100.0 * (0.62 * flick_norm + 0.38 * trk_pct)
	var err := 0.0
	if cur["errs"].size() > 0:
		for e in cur["errs"]:
			err += e
		err /= cur["errs"].size()
	rounds.append({"k": cur["k"], "stage": cur["stage"], "score": score, "acc": acc,
		"tp": tp, "tth_med": Analysis.median(cur["tth"]), "trk_pct": trk_pct,
		"err": err, "kills": cur["hits"], "n": cur["tth"].size()})
	round_i += 1

	var n_base: int = p["base"].size()
	var n_refine: int = p["refine"]
	var done := rounds.size()
	if done >= n_base and done < n_base + n_refine:
		# round adaptatif placé par UCB sur le processus gaussien
		var g := _fit_gp()
		var kn: float
		if g["ok"]:
			var tested: Array = []
			for r in rounds:
				tested.append(r["k"])
			kn = Analysis.gp_next_ucb(g["gp"], tested)
		else:
			kn = clamp(_fit_kopt() * (0.92 if done % 2 == 0 else 1.09),
				Analysis.K_MIN, Analysis.K_MAX)
		plan.append({"k": kn, "stage": "refine"})
	elif done == n_base + n_refine:
		var kp2 := _fit_kopt()
		for i in p["confirm"]:
			plan.append({"k": kp2, "stage": "confirm"})
	if round_i >= plan.size():
		_finalise()
	else:
		_begin_round()

# détrend de l'apprentissage puis régression GP ; met à jour `fit` (R² affiché)
func _fit_gp() -> Dictionary:
	var n := rounds.size()
	var xs: Array = []; var ys: Array = []; var ws: Array = []; var ts: Array = []
	for i in n:
		var r: Dictionary = rounds[i]
		xs.append(log(r["k"]))
		ys.append(r["score"])
		ws.append(float(maxi(1, int(r.get("n", r["kills"])))))
		ts.append(float(i) / maxf(n - 1.0, 1.0))
	var dt := Analysis.detrend(xs, ys, ws, ts)
	fit = Analysis.wfit(xs, dt["ys"], ws)
	var sn2 := Analysis.noise_from_fit(xs, dt["ys"], ws, fit)
	var g := Analysis.gp_fit(xs, dt["ys"], ws, sn2, true)
	if not g["ok"]:
		return {"ok": false}
	var sc := Analysis.gp_scan(g, 2.5, float(xs.min()) - 0.02, float(xs.max()) + 0.02)
	var bs := Analysis.bootstrap_range(xs, dt["ys"], ws, sn2, 140)
	# estimateur final : moyenne géométrique de l'argmax GP et de la médiane
	# des optima bootstrap (bagging → variance réduite)
	var kbest: float = sc["k"]
	if bs["ok"]:
		kbest = exp(0.5 * (log(float(sc["k"])) + log(float(bs["med"]))))
	return {"ok": true, "gp": g, "scan": sc, "bs": bs, "kbest": kbest,
		"xs": xs, "ys": dt["ys"], "ws": ws, "sn2": sn2, "trend": dt["trend"]}

func _fit_kopt() -> float:
	var g := _fit_gp()
	var kk: float
	if g["ok"]:
		kk = g["kbest"]
	else:
		var ks: Array = []; var ys: Array = []
		for r in rounds:
			ks.append(r["k"]); ys.append(r["score"])
		kk = Analysis.kopt_from(fit, ks, ys)
	# correction over/undershoot (pondérée) — biais dans le plateau, pas au-delà
	var werr := 0.0
	var wsum := 0.0
	for r in rounds:
		werr += r["err"] * max(1, r["kills"])
		wsum += max(1, r["kills"])
	if wsum > 0.0:
		werr /= wsum
	if werr > 0.07:
		kk *= 0.96
	elif werr < -0.07:
		kk *= 1.04
	return clamp(kk, Analysis.K_MIN, Analysis.K_MAX)

func _finalise() -> void:
	var g := _fit_gp()
	fres_scan = g["scan"] if g["ok"] else {}
	k_final = _fit_kopt()
	# validation par les rounds de confirmation
	var conf_scores: Array = []
	var best_meas := 0.0
	var best_k := 1.0
	for r in rounds:
		if r["stage"] == "confirm":
			conf_scores.append(r["score"])
		elif r["score"] > best_meas:
			best_meas = r["score"]
			best_k = r["k"]
	var conf_mean := 0.0
	for s in conf_scores:
		conf_mean += s
	if conf_scores.size() > 0:
		conf_mean /= conf_scores.size()
	var confirm_ok := conf_mean >= best_meas * 0.94
	if not confirm_ok:
		k_final = clamp(exp((log(k_final) + log(best_k)) / 2.0), Analysis.K_MIN, Analysis.K_MAX)
	# plage recommandée = plateau GP ∩ bootstrap de l'argmax (10e–90e pct)
	var relw := 1.0
	if g["ok"]:
		var bs: Dictionary = g["bs"]
		var lo: float = g["scan"]["lo"]
		var hi: float = g["scan"]["hi"]
		if bs["ok"]:
			lo = maxf(lo, bs["lo"])
			hi = minf(hi, bs["hi"])
			if lo > hi:
				lo = g["scan"]["lo"]
				hi = g["scan"]["hi"]
		k_lo = clampf(minf(lo, k_final * 0.96), Analysis.K_MIN, Analysis.K_MAX)
		k_hi = clampf(maxf(hi, k_final * 1.04), Analysis.K_MIN, Analysis.K_MAX)
		k_final = clampf(k_final, k_lo, k_hi)
		relw = (k_hi - k_lo) / maxf(k_final, 0.01)
	else:
		var ks2: Array = []; var ys2: Array = []; var ws2: Array = []
		for r in rounds:
			ks2.append(r["k"]); ys2.append(r["score"]); ws2.append(float(max(1, r["kills"])))
		var spread := Analysis.loo_spread(ks2, ys2, ws2)
		var half: float = clamp(max(0.04, spread * 0.5), 0.04, 0.15)
		k_lo = k_final * (1.0 - half)
		k_hi = k_final * (1.0 + half)
		relw = 2.0 * half
	if confirm_ok and fit["r2"] >= 0.45 and relw <= 0.24:
		confidence_txt = "confiance élevée (R² %.2f · plage ±%d%%)" % [fit["r2"], int(relw * 50)]
	elif confirm_ok or fit["r2"] >= 0.3 or relw <= 0.4:
		confidence_txt = "confiance moyenne (R² %.2f) — refais un test pour affiner" % fit["r2"]
	else:
		confidence_txt = "confiance faible (R² %.2f) — utilise le protocole PRÉCISION" % fit["r2"]
	_render_fres()

# ============================================================
#  CIBLES
# ============================================================
func _dir_from_angles(y_deg: float, p_deg: float) -> Vector3:
	var yr := deg_to_rad(y_deg)
	var pr := deg_to_rad(p_deg)
	return Vector3(-sin(yr) * cos(pr), sin(pr), -cos(yr) * cos(pr))

func _ang_of(node_pos: Vector3) -> float:
	var fwd := -cam.global_transform.basis.z
	var to_t := (node_pos - cam.position).normalized()
	return rad_to_deg(acos(clamp(fwd.dot(to_t), -1.0, 1.0)))

func _make_sphere(r_m: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r_m
	sm.height = r_m * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	m.roughness = 0.4
	mi.material_override = m
	return mi

func _clear_targets() -> void:
	for t in targets:
		if is_instance_valid(t["node"]):
			t["node"].queue_free()
	targets = []
	has_path = false
	if locate_snd != null:
		locate_snd.stop()

func _remove_target(t: Dictionary) -> void:
	if is_instance_valid(t["node"]):
		t["node"].queue_free()
	targets.erase(t)

# spawn générique d'une cible cliquable
func _spawn_click(r_m: float, cone_yaw: float, p_lo: float, p_hi: float, base_yaw: float, min_sep: float) -> Dictionary:
	var r_ang := rad_to_deg(asin(clamp(r_m / R_DIST, 0.0, 0.99)))
	var t_yaw := 0.0
	var t_pitch := 0.0
	for attempt in 24:
		t_yaw = base_yaw + randf_range(-cone_yaw, cone_yaw)
		t_pitch = randf_range(p_lo, p_hi)
		var ok := true
		for ex in targets:
			var dy: float = wrapf(t_yaw - ex["ang"].x, -180.0, 180.0)
			var dp: float = t_pitch - ex["ang"].y
			if Vector2(dy, dp).length() < ex["r_ang"] + r_ang + min_sep:
				ok = false
				break
		if ok:
			break
	var node := _make_sphere(r_m, UIKit.COL_ACCENT)
	node.position = cam.position + _dir_from_angles(t_yaw, t_pitch) * R_DIST
	add_child(node)
	var d0: float = Vector2(wrapf(t_yaw - yaw, -180.0, 180.0), t_pitch - pitch).length()
	var t := {"node": node, "ang": Vector2(t_yaw, t_pitch), "r_ang": r_ang,
		"born": Time.get_ticks_msec(), "d0": d0}
	targets.append(t)
	return t

func _spawn_finder_target() -> void:
	_clear_targets()
	# flick de 8 à 30° depuis le viseur : la cible reste dans le champ de vision,
	# et dans le quart de map devant le joueur (ancre ±45°) — pas de tour complet
	var t_yaw := yaw
	for attempt in 16:
		var off := randf_range(8.0, 30.0) * (1.0 if randf() < 0.5 else -1.0)
		t_yaw = yaw + off
		if absf(wrapf(t_yaw - anchor_yaw, -180.0, 180.0)) <= 45.0:
			break
		t_yaw = yaw - off   # l'autre côté si on sortait de la zone
		if absf(wrapf(t_yaw - anchor_yaw, -180.0, 180.0)) <= 45.0:
			break
	t_yaw = anchor_yaw + clampf(wrapf(t_yaw - anchor_yaw, -180.0, 180.0), -45.0, 45.0)
	var t_pitch: float = clamp(pitch * 0.3 + randf_range(-5.0, 9.0), -4.0, 18.0)
	var r_ang := rad_to_deg(asin(0.30 / R_DIST))
	var node := _make_sphere(0.30, UIKit.COL_ACCENT)
	node.position = cam.position + _dir_from_angles(t_yaw, t_pitch) * R_DIST
	add_child(node)
	var d0: float = Vector2(wrapf(t_yaw - yaw, -180.0, 180.0), t_pitch - pitch).length()
	targets = [{"node": node, "ang": Vector2(t_yaw, t_pitch), "r_ang": r_ang,
		"born": Time.get_ticks_msec(), "d0": d0}]
	_begin_path(Vector2(t_yaw, t_pitch))

func _begin_path(t_ang: Vector2) -> void:
	var d := Vector2(wrapf(t_ang.x - yaw, -180.0, 180.0), t_ang.y - pitch)
	path = {"p0": Vector2(yaw, pitch), "u": d.normalized(), "dist": d.length(),
		"last_t": Time.get_ticks_msec(), "last_proj": 0.0, "peak": 0.0, "ballistic": -1.0}
	has_path = true

func _record_path() -> void:
	if not has_path:
		return
	var t := Time.get_ticks_msec()
	var proj: float = (Vector2(yaw, pitch) - path["p0"]).dot(path["u"])
	var dt: float = max(0.001, (t - path["last_t"]) / 1000.0)
	var spd: float = abs(proj - path["last_proj"]) / dt
	if spd > path["peak"]:
		path["peak"] = spd
	if path["ballistic"] < 0.0 and path["peak"] > 60.0 and spd < path["peak"] * 0.15 and proj > path["dist"] * 0.35:
		path["ballistic"] = proj
	path["last_proj"] = proj
	path["last_t"] = t

func _ballistic_err() -> float:
	if not has_path or path["dist"] <= 0.5:
		return 0.0
	var bal: float = path["ballistic"] if path["ballistic"] >= 0.0 else path["last_proj"]
	return clamp(bal / path["dist"] - 1.0, -0.8, 0.8)

func _pop_fx(pos: Vector3, r_m: float, fx_col: Color = Color(1.0, 0.28, 0.33, 0.8)) -> void:
	var mi := _make_sphere(r_m, UIKit.COL_ACCENT)
	var m: StandardMaterial3D = mi.material_override
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx_col.a = 0.8
	m.albedo_color = fx_col
	m.emission_enabled = false
	mi.position = pos
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 2.4, 0.18)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.chain().tween_callback(mi.queue_free)

# ============================================================
#  TIR
# ============================================================
func _shoot() -> void:
	if Time.get_ticks_msec() < freeze_until:
		return
	if mode == Mode.F_TRACK:
		return
	if targets.is_empty():
		return
	# meilleure cible sous le viseur
	var hit_t := {}
	var best_ang := 1e9
	for t in targets:
		var a := _ang_of(t["node"].position)
		if a <= t["r_ang"] and a < best_ang:
			best_ang = a
			hit_t = t
	if hit_t.is_empty():
		snd_miss.play()
		if mode == Mode.F_FLICK:
			cur["misses"] += 1
			# le raté élargit la largeur effective We (ISO 9241-9)
			if not _finder_warmup() and not targets.is_empty():
				var nd := 1e9
				for t2 in targets:
					nd = minf(nd, _ang_of(t2["node"].position))
				cur["ends"].append(minf(nd, 25.0))
		elif mode == Mode.TRAIN:
			cur["misses"] += 1
			t_combo = 0
			# clic « trop tôt » : raté mais tout près d'une cible (flick pas fini)
			var early := false
			for t in targets:
				if _ang_of(t["node"].position) <= t["r_ang"] * 3.0:
					early = true
					break
			rec_clicks.append({"t": _train_t(), "ang": Vector2(yaw, pitch), "hit": false, "early": early})
		_refresh_play_hud()
		return
	snd_hit.play()
	var tth: float = (Time.get_ticks_msec() - hit_t["born"]) / 1000.0
	var w_diam: float = hit_t["r_ang"] * 2.0
	var fitts_id := 0.0
	if w_diam > 0.01:
		fitts_id = log(1.0 + hit_t["d0"] / w_diam) / log(2.0)
	if pop_enabled:
		_pop_fx(hit_t["node"].position, max(0.16, hit_t["r_ang"] / 57.3 * R_DIST))
	crosshair.flash_hit()
	if mode == Mode.F_FLICK:
		cur["hits"] += 1
		if not _finder_warmup():
			cur["tth"].append(tth)
			cur["sum_id"] += fitts_id
			cur["errs"].append(_ballistic_err())
			cur["d0s"].append(hit_t["d0"])
			cur["ends"].append(best_ang)
		_remove_target(hit_t)
		freeze_until = Time.get_ticks_msec() + 130
		var respawn := func() -> void:
			if mode == Mode.F_FLICK:
				_spawn_finder_target()
		get_tree().create_timer(0.13).timeout.connect(respawn)
	elif mode == Mode.SANDBOX:
		_remove_target(hit_t)
		freeze_until = Time.get_ticks_msec() + 130
		var respawn2 := func() -> void:
			if mode == Mode.SANDBOX:
				_spawn_finder_target()
		get_tree().create_timer(0.13).timeout.connect(respawn2)
	elif mode == Mode.TRAIN:
		var m: Dictionary = t_cfg
		cur["hits"] += 1
		cur["tth"].append(tth)
		if int(m.get("simul", 1)) == 1:
			cur["errs"].append(_ballistic_err())
		t_combo += 1
		t_best_streak = max(t_best_streak, t_combo)
		t_score += 100 + 4 * min(t_combo, 25)
		rec_clicks.append({"t": _train_t(), "ang": Vector2(yaw, pitch), "hit": true, "early": false})
		if hit_t.has("rec"):
			hit_t["rec"]["t1"] = _train_t()
			hit_t["rec"]["ang1"] = hit_t["ang"]
			hit_t["rec"]["fate"] = "hit"
		if hit_t.has("cell"):
			grid_last = int(hit_t["cell"])
		_remove_target(hit_t)
		if int(m.get("simul", 1)) == 1:
			freeze_until = Time.get_ticks_msec() + 110
			var respawn3 := func() -> void:
				if mode == Mode.TRAIN:
					_spawn_train_target()
			get_tree().create_timer(0.11).timeout.connect(respawn3)
		else:
			_spawn_train_target()
	_refresh_play_hud()

# ============================================================
#  TRACKING
# ============================================================
func _spawn_tracker(p: Dictionary) -> void:
	_clear_targets()
	trk_p = p
	trk_anchor_yaw = yaw
	trk_yaw = yaw + (0.0 if p.get("kind", "smooth") == "orbit" else 8.0)
	trk_v = p.get("v", 24.0)
	trk_pitch_base = clamp(pitch * 0.3 + 6.0, 2.0, 14.0)
	trk_pitch = trk_pitch_base
	trk_pv = p.get("v", 20.0)
	trk_ph = randf_range(0.0, 6.0)
	trk_flip_in = randf_range(p.get("flip_lo", 0.3), p.get("flip_hi", 0.8))
	var r: float = p.get("r", 0.33)
	var node := _make_sphere(r, UIKit.COL_ACCENT)
	add_child(node)
	targets = [{"node": node, "ang": Vector2.ZERO, "r_ang": rad_to_deg(asin(r / R_DIST)),
		"born": Time.get_ticks_msec(), "d0": 0.0}]
	trk_active = true

func _update_track(delta: float) -> void:
	if not trk_active or targets.is_empty():
		return
	var t: Dictionary = targets[0]
	var kind: String = trk_p.get("kind", "smooth")
	var band: float = trk_p.get("band", 26.0)
	var amp: float = trk_p.get("pitch_amp", 3.5)
	var v0: float = trk_p.get("v", 24.0)
	var t_pitch := trk_pitch_base
	match kind:
		"smooth":
			trk_v += randf_range(-1.0, 1.0) * 3.3 * v0 * delta
			trk_v = clamp(trk_v, -v0 * 1.75, v0 * 1.75)
			if absf(trk_v) < v0 * 0.58:
				trk_v = v0 * 0.58 * (1.0 if trk_v >= 0.0 else -1.0)
			trk_yaw += trk_v * delta
			trk_ph += delta * 1.7
			t_pitch = trk_pitch_base + sin(trk_ph) * amp
		"react":
			# vitesse constante, inversions brutales aléatoires
			trk_flip_in -= delta
			if trk_flip_in <= 0.0:
				trk_v = -trk_v * randf_range(0.9, 1.1)
				trk_flip_in = randf_range(trk_p.get("flip_lo", 0.25), trk_p.get("flip_hi", 0.7))
			trk_yaw += trk_v * delta
			trk_ph += delta * 1.7
			t_pitch = trk_pitch_base + sin(trk_ph) * amp
		"orbit":
			trk_ph += delta * trk_p.get("spd", 1.5)
			trk_yaw = trk_anchor_yaw + sin(trk_ph) * band
			t_pitch = trk_pitch_base + cos(trk_ph) * amp
		"vert":
			trk_pv += randf_range(-1.0, 1.0) * 3.3 * v0 * delta
			trk_pv = clamp(trk_pv, -v0 * 1.75, v0 * 1.75)
			if absf(trk_pv) < v0 * 0.58:
				trk_pv = v0 * 0.58 * (1.0 if trk_pv >= 0.0 else -1.0)
			trk_pitch += trk_pv * delta
			if trk_pitch > trk_pitch_base + amp:
				trk_pitch = trk_pitch_base + amp
				trk_pv = -absf(trk_pv)
			elif trk_pitch < maxf(trk_pitch_base - amp, -3.0):
				trk_pitch = maxf(trk_pitch_base - amp, -3.0)
				trk_pv = absf(trk_pv)
			trk_ph += delta * 1.3
			trk_yaw = trk_anchor_yaw + sin(trk_ph) * band
			t_pitch = trk_pitch
	if kind == "smooth" or kind == "react":
		if trk_yaw > trk_anchor_yaw + band:
			trk_yaw = trk_anchor_yaw + band
			trk_v = -absf(trk_v)
		elif trk_yaw < trk_anchor_yaw - band:
			trk_yaw = trk_anchor_yaw - band
			trk_v = absf(trk_v)
	t["node"].position = cam.position + _dir_from_angles(trk_yaw, t_pitch) * R_DIST
	if mode == Mode.TRAIN:
		var tt := _train_t()
		if rec_tgt.is_empty() or tt - rec_tgt[rec_tgt.size() - 1].x >= 0.005:
			rec_tgt.append(Vector3(tt, trk_yaw, t_pitch))
			rec_on.append(trk_on)
	var ang := _ang_of(t["node"].position)
	trk_on = ang <= t["r_ang"] + 0.55
	cur["trk_tot"] += delta
	if trk_on:
		cur["trk_on"] += delta
		if mode == Mode.TRAIN:
			t_score += int(round(250.0 * delta))
	var m: StandardMaterial3D = t["node"].material_override
	m.emission = UIKit.COL_ACCENT2 if trk_on else UIKit.COL_ACCENT
	m.albedo_color = UIKit.COL_ACCENT2 if trk_on else UIKit.COL_ACCENT

# ============================================================
#  ENTRAÎNEMENT — flow
# ============================================================
func _start_train(mk: String) -> void:
	t_mode = mk
	t_cfg = _train_cfg(mk, custom)
	t_ranked = custom.is_empty()
	_read_inputs()
	_store_game_inputs()
	_save_prefs()
	_apply_camera_fov()
	k = 1.0
	t_score = 0
	t_combo = 0
	t_best_streak = 0
	cur = {"hits": 0, "misses": 0, "tth": [], "errs": [], "sum_id": 0.0, "trk_on": 0.0, "trk_tot": 0.0}
	_rp_clear()
	_clear_targets()
	trk_active = false
	var m: Dictionary = t_cfg
	cnt_round_lbl.text = "%s · %d S%s" % [m["name"], t_dur, "" if t_ranked else " · PERSONNALISÉ"]
	cnt_score_lbl.text = str(m["desc"]) if t_ranked else "paramètres personnalisés — score non classé"
	hud_l1.text = "%s · %ds%s" % [m["name"].to_lower(), t_dur, "" if t_ranked else " · perso"]
	mode = Mode.COUNT
	count_ctx = "train"
	count_timer = 2.4
	hud_root.visible = true
	_show_only(count_panel)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# temps écoulé depuis le début du run (s)
func _train_t() -> float:
	return clampf(float(t_dur) - phase_timer, 0.0, float(t_dur))

func _start_train_run() -> void:
	mode = Mode.TRAIN
	paused = false
	phase_timer = float(t_dur)
	rec_samples = []
	rec_tgt = []
	rec_on = []
	rec_targets = []
	rec_clicks = []
	rec_last_t = -1.0
	var m: Dictionary = t_cfg
	if m["type"] == "click":
		anchor_yaw = yaw
		grid_last = -1
		if m.get("locate", false):
			hud_hint.text = "écoute le ping 3D, tourne-toi vers la cible et flicke"
		elif m.get("ttl", 0.0) > 0.0:
			hud_hint.text = "clique les cibles avant qu'elles expirent"
		else:
			hud_hint.text = "clique les cibles"
		for i in int(m.get("simul", 1)):
			_spawn_train_target()
	else:
		hud_hint.text = "garde le viseur sur la cible"
		_spawn_tracker(m["trk"])
	_refresh_play_hud()

func _spawn_train_target() -> void:
	var m: Dictionary = t_cfg
	if m.get("locate", false):
		_spawn_locate_target(m)
		return
	if m.has("grid_n"):
		_spawn_grid_target(m)
		return
	var base := anchor_yaw if m.get("anchored", false) else yaw
	var t := _spawn_click(m["r"], m["cone"], m["p_lo"], m["p_hi"], base, 1.5)
	var mv: float = m.get("move", 0.0)
	if mv > 0.0:
		t["mv"] = mv * (1.0 if randf() < 0.5 else -1.0)
		t["mbase"] = base
	var rec := {"t0": _train_t(), "ang0": t["ang"], "t1": -1.0, "ang1": t["ang"],
		"r_ang": t["r_ang"], "fate": "", "path": [], "path_t": -1.0}
	t["rec"] = rec
	rec_targets.append(rec)
	if int(m.get("simul", 1)) == 1:
		_begin_path(t["ang"])

# gridshot : les cibles occupent les cellules d'une grille N×N ancrée devant le
# joueur. Écart entre cellules = grid_step (réglable par « écart des cibles »),
# borné pour que les sphères ne se chevauchent jamais.
func _spawn_grid_target(m: Dictionary) -> void:
	var n: int = maxi(2, int(m["grid_n"]))
	var r_m: float = float(m["r"])
	var r_ang := rad_to_deg(asin(clamp(r_m / R_DIST, 0.0, 0.99)))
	var step: float = maxf(float(m["grid_step"]), r_ang * 2.0 * 1.08)   # jamais de chevauchement
	var cx := anchor_yaw
	var cy := (float(m["p_lo"]) + float(m["p_hi"])) * 0.5
	# cellules libres = celles qu'aucune cible active n'occupe
	var used := {}
	for ex in targets:
		if ex.has("cell"):
			used[int(ex["cell"])] = true
	var free: Array = []
	for c in n * n:
		if not used.has(c):
			free.append(c)
	if free.is_empty():
		return
	# éviter de réapparaître pile sur la case qu'on vient de toucher
	if free.size() > 1 and grid_last >= 0 and free.has(grid_last):
		free.erase(grid_last)
	var cell: int = free[randi() % free.size()]
	var half := float(n - 1) * 0.5
	var t_yaw := cx + (float(cell % n) - half) * step
	var t_pitch := cy + (float(cell / n) - half) * step
	var node := _make_sphere(r_m, UIKit.COL_ACCENT)
	node.position = cam.position + _dir_from_angles(t_yaw, t_pitch) * R_DIST
	add_child(node)
	var d0: float = Vector2(wrapf(t_yaw - yaw, -180.0, 180.0), t_pitch - pitch).length()
	var t := {"node": node, "ang": Vector2(t_yaw, t_pitch), "r_ang": r_ang,
		"born": Time.get_ticks_msec(), "d0": d0, "cell": cell}
	var mv: float = m.get("move", 0.0)
	if mv > 0.0:
		t["mv"] = mv * (1.0 if randf() < 0.5 else -1.0)
		t["mbase"] = cx
	targets.append(t)
	var rec := {"t0": _train_t(), "ang0": t["ang"], "t1": -1.0, "ang1": t["ang"],
		"r_ang": r_ang, "fate": "", "path": [], "path_t": -1.0}
	t["rec"] = rec
	rec_targets.append(rec)

# mode SONAR : la cible apparaît hors de l'écran (yaw 58–180° de part et d'autre
# du viseur, tout autour), pas trop haut ni bas ; un ping 3D indique sa direction
func _spawn_locate_target(m: Dictionary) -> void:
	var off := randf_range(58.0, 180.0) * (1.0 if randf() < 0.5 else -1.0)
	var t_yaw := yaw + off
	# la cible doit rester à hauteur visible : jamais sous le sol ni trop haut.
	# y_monde = cam.y + sin(pitch)·R_DIST, borné entre 0,7 et 3,6 m.
	var p_min := rad_to_deg(asin(clampf((0.7 - cam.position.y) / R_DIST, -1.0, 1.0)))
	var p_max := rad_to_deg(asin(clampf((3.6 - cam.position.y) / R_DIST, -1.0, 1.0)))
	var lo := maxf(float(m["p_lo"]), p_min)
	var hi := minf(float(m["p_hi"]), p_max)
	if hi < lo:
		hi = lo
	var t_pitch := randf_range(lo, hi)
	var r_m: float = float(m["r"])
	var r_ang := rad_to_deg(asin(clamp(r_m / R_DIST, 0.0, 0.99)))
	var node := _make_sphere(r_m, UIKit.COL_ACCENT)
	node.position = cam.position + _dir_from_angles(t_yaw, t_pitch) * R_DIST
	add_child(node)
	var d0: float = Vector2(wrapf(t_yaw - yaw, -180.0, 180.0), t_pitch - pitch).length()
	var t := {"node": node, "ang": Vector2(t_yaw, t_pitch), "r_ang": r_ang,
		"born": Time.get_ticks_msec(), "d0": d0}
	targets.append(t)
	var rec := {"t0": _train_t(), "ang0": t["ang"], "t1": -1.0, "ang1": t["ang"],
		"r_ang": r_ang, "fate": "", "path": [], "path_t": -1.0}
	t["rec"] = rec
	rec_targets.append(rec)
	# le ping suit la cible
	locate_snd.global_position = node.position
	if not locate_snd.playing:
		locate_snd.play()

# cibles mobiles (move) et éphémères (ttl) des modes réflexes
func _update_click_targets(delta: float, m: Dictionary) -> void:
	var mv: float = m.get("move", 0.0)
	var ttl: float = m.get("ttl", 0.0)
	if mv <= 0.0 and ttl <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var expired: Array = []
	var tt := _train_t()
	for t in targets:
		if mv > 0.0:
			var a: Vector2 = t["ang"]
			a.x += t["mv"] * delta
			var lim: float = m["cone"] + 4.0
			var off: float = wrapf(a.x - t["mbase"], -180.0, 180.0)
			if off > lim:
				a.x = t["mbase"] + lim
				t["mv"] = -absf(t["mv"])
			elif off < -lim:
				a.x = t["mbase"] - lim
				t["mv"] = absf(t["mv"])
			t["ang"] = a
			t["node"].position = cam.position + _dir_from_angles(a.x, a.y) * R_DIST
			if t.has("rec") and tt - t["rec"]["path_t"] >= 0.033:
				t["rec"]["path"].append(Vector3(tt, a.x, a.y))
				t["rec"]["path_t"] = tt
		if ttl > 0.0 and now - int(t["born"]) > int(ttl * 1000.0):
			expired.append(t)
	for t in expired:
		snd_miss.play()
		cur["misses"] += 1
		t_combo = 0
		if t.has("rec"):
			t["rec"]["t1"] = tt
			t["rec"]["ang1"] = t["ang"]
			t["rec"]["fate"] = "expire"
		_remove_target(t)
		_spawn_train_target()
	if not expired.is_empty():
		_refresh_play_hud()

# stats détaillées d'un run, envoyées au classement en ligne
func _run_stats(m: Dictionary) -> Dictionary:
	if str(m.get("type", "")) == "click":
		var shots: int = int(cur["hits"]) + int(cur["misses"])
		var acc := (float(cur["hits"]) / shots * 100.0) if shots > 0 else 0.0
		return {"acc": acc, "streak": t_best_streak, "hits": int(cur["hits"]), "shots": shots}
	# tracking : précision = temps sur la cible
	var pct: float = (float(cur["trk_on"]) / float(cur["trk_tot"]) * 100.0) if float(cur["trk_tot"]) > 0.0 else 0.0
	return {"acc": pct, "streak": 0, "hits": 0, "shots": 0}

func _end_train() -> void:
	snd_round.play()
	trk_active = false
	_clear_targets()
	var m: Dictionary = t_cfg
	var rec := _get_record(t_mode, t_dur)
	var new_rec := t_ranked and t_score > rec
	if new_rec:
		_set_record(t_mode, t_dur, t_score)
	tres_title.text = "%s · %d S%s" % [m["name"], t_dur, "" if t_ranked else " · PERSONNALISÉ"]
	tres_score.text = str(t_score)
	if not t_ranked:
		tres_record.text = "paramètres personnalisés — score non classé"
	elif new_rec:
		tres_record.text = "★ NOUVEAU RECORD (ancien : %d)" % rec if rec > 0 else "★ PREMIER RECORD ÉTABLI"
	else:
		tres_record.text = "record : %d" % rec
	# clôture des cibles encore vivantes pour le replay
	for rt in rec_targets:
		if rt["t1"] < 0.0:
			rt["t1"] = _train_t()
	_dash_fill(m)
	# tuiles de stats façon Aimlabs
	for ch in dash_chips_box.get_children():
		ch.queue_free()
	if m["type"] == "click":
		var tot: int = cur["hits"] + cur["misses"]
		var acc := (float(cur["hits"]) / tot * 100.0) if tot > 0 else 0.0
		_chip("RECORD", str(maxi(t_score, rec)) if t_ranked else (str(rec) if rec > 0 else "—"), UIKit.COL_ACCENT2)
		_chip("PRÉCÉDENT MEILLEUR", str(rec) if rec > 0 else "—", UIKit.COL_TEXT)
		_chip("PRÉCISION", "%.1f%%" % acc, UIKit.COL_TEXT)
		_chip("COUPS/TIRS", "%d/%d" % [cur["hits"], tot], UIKit.COL_TEXT)
		_chip("CIBLES TUÉES", str(cur["hits"]), UIKit.COL_TEXT)
		_chip("SÉRIE MAX", str(t_best_streak), UIKit.COL_TEXT)
	else:
		var pct: float = (cur["trk_on"] / cur["trk_tot"] * 100.0) if cur["trk_tot"] > 0.0 else 0.0
		_chip("RECORD", str(maxi(t_score, rec)) if t_ranked else (str(rec) if rec > 0 else "—"), UIKit.COL_ACCENT2)
		_chip("PRÉCÉDENT MEILLEUR", str(rec) if rec > 0 else "—", UIKit.COL_TEXT)
		_chip("TEMPS SUR CIBLE", "%.1f%%" % pct, UIKit.COL_TEXT)
		_chip("PLUS LONG DÉCROCHAGE", "%.1f s" % dash_worst_off, UIKit.COL_TEXT)
	# initialisation du replay première personne
	rp_dur = maxf(_train_t(), 0.5)
	rp_t = 0.0
	rp_playing = true
	rp_speed = 1.0
	_rp_classify(m["type"] != "click")
	_rp_clear()
	rp_overlay.track = m["type"] != "click"
	rp_time_ctl.dur = rp_dur
	rp_time_ctl.clicks = rec_clicks
	rp_play_btn.text = "⏸ PAUSE"
	for i in rp_speed_btns.size():
		UIKit.set_btn_selected(rp_speed_btns[i], i == 1)
	dash_mode_opt.select(MODE_ORDER.find(t_mode))
	mode = Mode.T_RESULTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud_root.visible = false
	_show_only(tres_panel)
	if pl_active:
		tres_pl_row.visible = true
		var last := pl_i >= pl_queue.size() - 1
		tres_pl_lbl.text = "PLAYLIST « %s » · exercice %d/%d" % [pl_play_name, pl_i + 1, pl_queue.size()]
		tres_pl_next.text = "TERMINER LA PLAYLIST ✓" if last else "EXERCICE SUIVANT ▶"
	else:
		tres_pl_row.visible = false
	# envoi au classement puis rafraîchissement du top de cet exercice
	lb_mode = t_mode
	lb_dur = t_dur
	for ch in dash_lb_grid.get_children():
		ch.queue_free()
	if not lb.configured():
		tres_net.text = ""
		dash_lb_status.text = "classement en ligne non configuré"
	elif not t_ranked:
		tres_net.text = "paramètres personnalisés → score non envoyé au classement"
		dash_lb_status.text = "chargement…"
		lb.fetch_top(t_mode, t_dur)
	elif pseudo == "":
		tres_net.text = "pas de pseudo → score non envoyé au classement (RÉGLAGES)"
		dash_lb_status.text = "chargement…"
		lb.fetch_top(t_mode, t_dur)
	else:
		tres_net.text = "envoi au classement…"
		dash_lb_status.text = "envoi du score…"
		lb.submit(pseudo, t_mode, t_dur, t_score, _run_stats(m))
		# nouveau record perso → le replay part au classement (▶ pour les autres)
		if new_rec:
			lb.submit_replay(pseudo, t_mode, t_dur, t_score, _replay_pack())
	# score du défi multijoueur
	if room_active and room_code != "" and pseudo != "" and room_played >= 0:
		room.submit(room_code, pseudo, room_played, t_score)
		tres_net.text += "  · score envoyé au défi (room %s)" % room_code
	room_active = false

# diagnostics « à améliorer » du dashboard
func _dash_fill(m: Dictionary) -> void:
	var lines: Array = []
	if m["type"] == "click":
		var tot: int = cur["hits"] + cur["misses"]
		var acc := float(cur["hits"]) / tot * 100.0 if tot > 0 else 0.0
		if acc < 70.0:
			lines.append("[color=#FF4655]■[/color] [b][color=#E9EEF6]Précision faible (%d%%)[/color][/b] — ralentis : vise d'abord, la vitesse viendra. Un tir sûr vaut mieux que deux ratés." % int(acc))
		elif acc < 85.0:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Précision moyenne (%d%%)[/color][/b] — vise 90%% : ajuste le dernier degré avant de cliquer." % int(acc))
		else:
			lines.append("[color=#7CE38B]■[/color] Précision solide (%d%%) — tu peux chercher plus de vitesse." % int(acc))
		var early := 0
		var missed := 0
		for c in rec_clicks:
			if not c["hit"]:
				missed += 1
				if c["early"]:
					early += 1
		if missed >= 3 and early * 2 >= missed:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Clics trop tôt[/color][/b] — %d de tes %d ratés sont partis juste à côté de la cible (✕ orange dans le replay) : laisse le viseur se poser une fraction de seconde." % [early, missed])
		if cur["errs"].size() > 3:
			var werr := 0.0
			for e in cur["errs"]:
				werr += e
			werr /= cur["errs"].size()
			if werr > 0.05:
				lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Overshoot (+%d%%)[/color][/b] — tes flicks dépassent la cible puis corrigent (arcs orange du replay). Freine plus tôt, ou baisse un peu ta sens." % int(werr * 100))
			elif werr < -0.05:
				lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Undershoot (%d%%)[/color][/b] — tes flicks s'arrêtent avant la cible. Engage plus franchement, ou monte un peu ta sens." % int(werr * 100))
			else:
				lines.append("[color=#7CE38B]■[/color] Flicks nets — dépassement moyen quasi nul.")
		var expired := 0
		for rt in rec_targets:
			if rt["fate"] == "expire":
				expired += 1
		if expired > 0:
			lines.append("[color=#FF4655]■[/color] [b][color=#E9EEF6]%d cible(s) expirée(s)[/color][/b] — trop lent à réagir : garde le viseur au centre de la zone entre deux cibles." % expired)
		var med: float = Analysis.median(cur["tth"])
		if med > 0.0:
			lines.append("[color=#57D4FF]■[/color] Temps par cible médian %.2f s · meilleure série %d." % [med, t_best_streak])
		_deep_click(m, lines)
	else:
		var pct := 0.0
		if cur["trk_tot"] > 0.0:
			pct = cur["trk_on"] / cur["trk_tot"] * 100.0
		if pct < 45.0:
			lines.append("[color=#FF4655]■[/color] [b][color=#E9EEF6]%d%% sur la cible[/color][/b] — colle au mouvement au lieu de le rattraper : bouge avec la cible, pas après elle." % int(pct))
		elif pct < 70.0:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]%d%% sur la cible[/color][/b] — bien, mais tu décroches sur les changements de direction (segments rouges du replay)." % int(pct))
		else:
			lines.append("[color=#7CE38B]■[/color] %d%% sur la cible — tracking solide." % int(pct))
		# plus longue période hors cible
		var worst := 0.0
		var run := 0.0
		for i in rec_on.size():
			if rec_on[i]:
				run = 0.0
			else:
				var dt := 0.005 if i == 0 else float(rec_tgt[i].x - rec_tgt[i - 1].x)
				run += dt
				worst = maxf(worst, run)
		dash_worst_off = worst
		if worst > 0.8:
			lines.append("[color=#FFB454]■[/color] Plus long décrochage : [b][color=#E9EEF6]%.1f s[/color][/b] — repère-le dans le replay pour voir ce qui t'a perdu." % worst)
		_deep_track(lines)
	lines.append("[color=#7B8798]Le replay rejoue exactement ta partie en vue première personne : la traînée suit ton viseur, les couleurs montrent où tu perds des points.[/color]")
	dash_diag.text = "\n".join(lines)

# ============================================================
#  REPLAY PREMIÈRE PERSONNE
#  La caméra rejoue exactement les mouvements enregistrés et les
#  cibles réapparaissent aux mêmes instants : re-simulation fidèle.
# ============================================================
func _rp_seek(tt: float) -> void:
	rp_t = clampf(tt, 0.0, rp_dur)

func _rp_clear() -> void:
	for n in rp_nodes.values():
		if is_instance_valid(n):
			n.queue_free()
	rp_nodes = {}
	if rp_trk_node != null and is_instance_valid(rp_trk_node):
		rp_trk_node.queue_free()
	rp_trk_node = null

# index du dernier échantillon de viseur dont t <= tt
func _rp_idx(tt: float) -> int:
	var lo := 0
	var hi := rec_samples.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if rec_samples[mid].x <= tt:
			lo = mid
		else:
			hi = mid - 1
	return lo

func _rp_tgt_idx(tt: float) -> int:
	var lo := 0
	var hi := rec_tgt.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if rec_tgt[mid].x <= tt:
			lo = mid
		else:
			hi = mid - 1
	return lo

# centre angulaire d'une cible enregistrée à l'instant st
func _rec_center(rt: Dictionary, st: float) -> Vector2:
	var pth: Array = rt["path"]
	if not pth.is_empty():
		for p in pth:
			if p.x >= st:
				return Vector2(p.y, p.z)
		return Vector2(pth[-1].y, pth[-1].z)
	var t1: float = rt["t1"]
	if t1 <= rt["t0"]:
		return rt["ang0"]
	var f: float = clampf((st - rt["t0"]) / (t1 - rt["t0"]), 0.0, 1.0)
	return rt["ang0"].lerp(rt["ang1"], f)

# classe chaque échantillon : 0 trajet, 1 sur cible, 2 défaut (dépassement / hors cible)
func _rp_classify(track: bool) -> void:
	rp_cls = PackedInt32Array()
	rp_cls.resize(rec_samples.size())
	if track:
		if rec_on.is_empty():
			return
		var j := 0
		for i in rec_samples.size():
			while j < rec_on.size() - 1 and rec_tgt[j].x < rec_samples[i].x:
				j += 1
			rp_cls[i] = 1 if bool(rec_on[j]) else 2
		return
	var prev_d := 1e9
	for i in rec_samples.size():
		var st: float = rec_samples[i].x
		var aim := Vector2(rec_samples[i].y, rec_samples[i].z)
		var best := 1e9
		var best_r := 1.0
		for rt in rec_targets:
			if rt["t0"] > st:
				break
			if rt["t1"] >= 0.0 and rt["t1"] < st:
				continue
			var dd := (aim - _rec_center(rt, st)).length()
			if dd < best:
				best = dd
				best_r = rt["r_ang"]
		var k2 := 0
		if best <= best_r * 1.15:
			k2 = 1
		elif best < best_r * 5.0 and best > prev_d + 0.015:
			k2 = 2
		rp_cls[i] = k2
		prev_d = best

func _rp_update(delta: float) -> void:
	if rec_samples.is_empty():
		return
	if rp_playing:
		rp_t += delta * rp_speed
		if rp_t > rp_dur:
			rp_t = 0.0
	# caméra : exactement là où le joueur regardait
	var i := _rp_idx(rp_t)
	var s: Vector3 = rec_samples[i]
	if i < rec_samples.size() - 1:
		var s2: Vector3 = rec_samples[i + 1]
		var f := clampf((rp_t - s.x) / maxf(s2.x - s.x, 0.0001), 0.0, 1.0)
		yaw = lerpf(s.y, s2.y, f)
		pitch = lerpf(s.z, s2.z, f)
	else:
		yaw = s.y
		pitch = s.z
	cam.rotation_degrees = Vector3(pitch, yaw, 0)
	var mm: Dictionary = t_cfg
	if str(mm.get("type", "click")) == "click":
		for idx in rec_targets.size():
			var rt: Dictionary = rec_targets[idx]
			var t1: float = rt["t1"] if rt["t1"] >= 0.0 else rp_dur
			var alive: bool = rt["t0"] <= rp_t and rp_t <= t1
			# rayon reconstruit depuis r_ang : le replay est auto-suffisant
			var r_m: float = sin(deg_to_rad(float(rt["r_ang"]))) * R_DIST
			if alive:
				if not rp_nodes.has(idx):
					rp_nodes[idx] = _make_sphere(r_m, UIKit.COL_ACCENT)
					add_child(rp_nodes[idx])
				var c := _rec_center(rt, rp_t)
				rp_nodes[idx].position = cam.position + _dir_from_angles(c.x, c.y) * R_DIST
			elif rp_nodes.has(idx):
				var n: MeshInstance3D = rp_nodes[idx]
				if rp_t > t1 and rp_t - t1 < 0.4:
					_pop_fx(n.position, r_m,
						UIKit.COL_OK if rt["fate"] == "hit" else Color(1.0, 0.28, 0.33, 0.8))
				n.queue_free()
				rp_nodes.erase(idx)
	elif not rec_tgt.is_empty():
		# cible de tracking : cyan quand tu étais dessus, rouge sinon
		if rp_trk_node == null or not is_instance_valid(rp_trk_node):
			var mtrk: Dictionary = mm.get("trk", {})
			rp_trk_node = _make_sphere(float(mtrk.get("r", 0.33)), UIKit.COL_ACCENT)
			add_child(rp_trk_node)
		var j := _rp_tgt_idx(rp_t)
		rp_trk_node.position = cam.position + _dir_from_angles(rec_tgt[j].y, rec_tgt[j].z) * R_DIST
		var on: bool = j < rec_on.size() and bool(rec_on[j])
		var mat: StandardMaterial3D = rp_trk_node.material_override
		mat.emission = UIKit.COL_ACCENT2 if on else UIKit.COL_ACCENT
		mat.albedo_color = UIKit.COL_ACCENT2 if on else UIKit.COL_ACCENT
	rp_time_ctl.tcur = rp_t
	rvw_time_ctl.tcur = rp_t

# ---- sérialisation du replay pour le classement en ligne ----
# viseur ré-échantillonné à ~66 Hz puis var_to_bytes → deflate → base64
# (≈ 30–80 Ko selon la durée) ; envoyé à chaque record perso
func _replay_pack() -> String:
	var smp := PackedFloat32Array()
	var last := -1.0
	for s in rec_samples:
		if s.x - last >= 0.014:
			smp.append(s.x)
			smp.append(s.y)
			smp.append(s.z)
			last = s.x
	var tgt := PackedFloat32Array()
	var onb := PackedByteArray()
	for i in rec_tgt.size():
		tgt.append(rec_tgt[i].x)
		tgt.append(rec_tgt[i].y)
		tgt.append(rec_tgt[i].z)
		onb.append(1 if bool(rec_on[i]) else 0)
	var tgs: Array = []
	for rt in rec_targets:
		var pp := PackedFloat32Array()
		for p in rt["path"]:
			pp.append(p.x)
			pp.append(p.y)
			pp.append(p.z)
		tgs.append({"t0": rt["t0"], "x0": rt["ang0"].x, "y0": rt["ang0"].y,
			"t1": rt["t1"], "x1": rt["ang1"].x, "y1": rt["ang1"].y,
			"r": rt["r_ang"], "f": rt["fate"], "p": pp})
	var cks: Array = []
	for c in rec_clicks:
		cks.append({"t": c["t"], "x": c["ang"].x, "y": c["ang"].y, "h": c["hit"], "e": c["early"]})
	var r_m: float = float(t_cfg["r"]) if str(t_cfg["type"]) == "click" else float(t_cfg["trk"].get("r", 0.33))
	var d := {"v": 1, "mode": t_mode, "dur": t_dur, "score": t_score,
		"type": t_cfg["type"], "r": r_m,
		"smp": smp, "tgt": tgt, "on": onb, "tg": tgs, "ck": cks}
	return Marshalls.raw_to_base64(var_to_bytes(d).compress(FileAccess.COMPRESSION_DEFLATE))

func _replay_unpack(b64: String) -> Dictionary:
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return {}
	var bytes := raw.decompress_dynamic(16 << 20, FileAccess.COMPRESSION_DEFLATE)
	if bytes.is_empty():
		return {}
	var d = bytes_to_var(bytes)   # sans allow_objects : sûr sur données distantes
	if not (d is Dictionary) or int(d.get("v", 0)) != 1:
		return {}
	var smp: PackedFloat32Array = d.get("smp", PackedFloat32Array())
	var samples: Array = []
	for i in range(0, smp.size() - 2, 3):
		samples.append(Vector3(smp[i], smp[i + 1], smp[i + 2]))
	if samples.size() < 4:
		return {}
	var tgtp: PackedFloat32Array = d.get("tgt", PackedFloat32Array())
	var tgt: Array = []
	for i in range(0, tgtp.size() - 2, 3):
		tgt.append(Vector3(tgtp[i], tgtp[i + 1], tgtp[i + 2]))
	var onb: PackedByteArray = d.get("on", PackedByteArray())
	var on: Array = []
	for b in onb:
		on.append(b != 0)
	var targets2: Array = []
	for tg in d.get("tg", []):
		var pth: Array = []
		var pp: PackedFloat32Array = tg.get("p", PackedFloat32Array())
		for i in range(0, pp.size() - 2, 3):
			pth.append(Vector3(pp[i], pp[i + 1], pp[i + 2]))
		targets2.append({"t0": float(tg["t0"]), "ang0": Vector2(tg["x0"], tg["y0"]),
			"t1": float(tg["t1"]), "ang1": Vector2(tg["x1"], tg["y1"]),
			"r_ang": float(tg["r"]), "fate": str(tg["f"]), "path": pth, "path_t": -1.0})
	var clicks: Array = []
	for c in d.get("ck", []):
		clicks.append({"t": float(c["t"]), "ang": Vector2(c["x"], c["y"]),
			"hit": bool(c["h"]), "early": bool(c["e"])})
	return {"mode": str(d.get("mode", "")), "dur": int(d.get("dur", 60)),
		"score": int(d.get("score", 0)), "type": str(d.get("type", "click")),
		"r": float(d.get("r", 0.3)), "samples": samples, "tgt": tgt, "on": on,
		"targets": targets2, "clicks": clicks}

# ---- analyse approfondie des modes click ----
# décompose chaque kill en réaction → flick → ajustement à partir du replay,
# cherche un biais directionnel et compare les deux moitiés de session
func _deep_click(m: Dictionary, lines: Array) -> void:
	if int(m.get("simul", 1)) == 1 and rec_samples.size() > 30:
		var reacts: Array = []
		var flicks: Array = []
		var adjusts: Array = []
		var tth_left: Array = []
		var tth_right: Array = []
		var si := 0
		for rt in rec_targets:
			if rt["fate"] != "hit":
				continue
			while si < rec_samples.size() and rec_samples[si].x < rt["t0"]:
				si += 1
			# vitesse angulaire du viseur pendant la vie de la cible
			var i := si
			var peak := 0.0
			var t_react := -1.0
			var t_bal := -1.0
			var prev: Vector3 = rec_samples[maxi(si - 1, 0)]
			while i < rec_samples.size() and rec_samples[i].x <= rt["t1"] + 0.001:
				var s: Vector3 = rec_samples[i]
				var dt := maxf(s.x - prev.x, 0.001)
				var spd := Vector2(s.y - prev.y, s.z - prev.z).length() / dt
				if t_react < 0.0 and spd > 30.0:
					t_react = s.x - rt["t0"]
				if spd > peak:
					peak = spd
				elif t_react >= 0.0 and t_bal < 0.0 and peak > 60.0 and spd < peak * 0.15:
					t_bal = s.x - rt["t0"]
				prev = s
				i += 1
			var life: float = rt["t1"] - rt["t0"]
			if t_react >= 0.0 and life > 0.05:
				reacts.append(t_react)
				if t_bal > t_react:
					flicks.append(t_bal - t_react)
					adjusts.append(maxf(life - t_bal, 0.0))
			# biais directionnel : la cible était-elle à gauche ou à droite ?
			if si > 0 and life > 0.05:
				var dy: float = wrapf(rt["ang0"].x - rec_samples[maxi(si - 1, 0)].y, -180.0, 180.0)
				if absf(dy) > 3.0:
					(tth_left if dy > 0.0 else tth_right).append(life)
		if reacts.size() >= 5 and flicks.size() >= 5:
			var mr: float = Analysis.median(reacts)
			var mf: float = Analysis.median(flicks)
			var ma: float = Analysis.median(adjusts)
			lines.append("[color=#57D4FF]■[/color] [b][color=#E9EEF6]Kill médian décomposé[/color][/b] : réaction %.2f s → flick %.2f s → ajustement %.2f s." % [mr, mf, ma])
			if ma >= mr and ma >= mf and ma > 0.22:
				lines.append("    ↳ c'est [b][color=#E9EEF6]l'ajustement final[/color][/b] qui te coûte le plus : travaille MICROSHOT / MICRODOT, ou essaie une sens un poil plus basse.")
			elif mr >= mf and mr >= ma and mr > 0.28:
				lines.append("    ↳ c'est [b][color=#E9EEF6]la réaction[/color][/b] qui te coûte le plus : pack RÉFLEXES, et garde le viseur au centre de la zone entre deux cibles.")
			elif mf > 0.28:
				lines.append("    ↳ c'est [b][color=#E9EEF6]le flick lui-même[/color][/b] qui est lent : ose un geste de bras plus franc (WIDE FLICK), quitte à corriger ensuite.")
		if tth_left.size() >= 4 and tth_right.size() >= 4:
			var ml: float = Analysis.median(tth_left)
			var mrgt: float = Analysis.median(tth_right)
			if ml > mrgt * 1.25:
				lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Biais directionnel[/color][/b] : tes cibles à gauche prennent %d%% plus de temps qu'à droite — entraîne les flicks vers la gauche." % int((ml / mrgt - 1.0) * 100))
			elif mrgt > ml * 1.25:
				lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Biais directionnel[/color][/b] : tes cibles à droite prennent %d%% plus de temps qu'à gauche — entraîne les flicks vers la droite." % int((mrgt / ml - 1.0) * 100))
	# régularité sur la durée : 1re moitié vs 2e moitié
	var h := [0, 0, 0, 0]  # hits1, miss1, hits2, miss2
	for c in rec_clicks:
		var late: int = 2 if c["t"] > float(t_dur) * 0.5 else 0
		h[late + (0 if c["hit"] else 1)] += 1
	var n1: int = h[0] + h[1]
	var n2: int = h[2] + h[3]
	if n1 >= 8 and n2 >= 8:
		var a1 := float(h[0]) / n1 * 100.0
		var a2 := float(h[2]) / n2 * 100.0
		if a1 - a2 > 12.0:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Tu t'effondres sur la durée[/color][/b] : précision %d%% en 1re moitié → %d%% en 2e. La tension monte — relâche le grip, respire entre les cibles." % [int(a1), int(a2)])
		elif a2 - a1 > 12.0:
			lines.append("[color=#57D4FF]■[/color] [b][color=#E9EEF6]Démarrage froid[/color][/b] : %d%% en 1re moitié → %d%% en 2e. Échauffe-toi 2-3 minutes avant de jouer sérieusement." % [int(a1), int(a2)])

# ---- analyse approfondie du tracking ----
# retard/avance moyen derrière la cible + délai de réaction aux inversions
func _deep_track(lines: Array) -> void:
	if rec_tgt.size() < 60 or rec_samples.size() < 60:
		return
	var lag_sum := 0.0
	var lag_n := 0
	var flips: Array = []       # [t de l'inversion, nouveau signe]
	var prev_v := 0.0
	var j := 0
	for i in range(1, rec_tgt.size()):
		var dt: float = rec_tgt[i].x - rec_tgt[i - 1].x
		if dt <= 0.0:
			continue
		var v: float = (rec_tgt[i].y - rec_tgt[i - 1].y) / dt
		while j < rec_samples.size() - 1 and rec_samples[j].x < rec_tgt[i].x:
			j += 1
		if absf(v) > 6.0:
			lag_sum += (rec_samples[j].y - rec_tgt[i].y) * signf(v)
			lag_n += 1
			if prev_v != 0.0 and signf(v) != signf(prev_v):
				flips.append([rec_tgt[i].x, signf(v)])
			prev_v = v
	if lag_n > 30:
		var lag := lag_sum / lag_n
		if lag < -0.55:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Tu traînes %.1f° derrière la cible[/color][/b] en moyenne — tu rattrapes au lieu d'accompagner. Anticipe : bouge AVEC la cible." % absf(lag))
		elif lag > 0.55:
			lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Tu devances la cible de %.1f°[/color][/b] en moyenne — tu sur-anticipes. Cale-toi sur sa vitesse réelle." % lag)
		else:
			lines.append("[color=#7CE38B]■[/color] Bien calé sur la cible (écart moyen %.1f°)." % absf(lag))
	# délai de re-synchronisation après une inversion de direction
	if flips.size() >= 4:
		var delays: Array = []
		var k2 := 1
		for f in flips:
			var tf: float = f[0]
			var sgn: float = f[1]
			while k2 < rec_samples.size() - 1 and rec_samples[k2].x < tf:
				k2 += 1
			var k3 := k2
			while k3 < rec_samples.size() - 1 and rec_samples[k3].x < tf + 1.0:
				var dt2: float = rec_samples[k3 + 1].x - rec_samples[k3].x
				if dt2 > 0.0:
					var av: float = (rec_samples[k3 + 1].y - rec_samples[k3].y) / dt2
					if signf(av) == sgn and absf(av) > 10.0:
						delays.append(rec_samples[k3].x - tf)
						break
				k3 += 1
		if delays.size() >= 3:
			var mdel: float = Analysis.median(delays)
			if mdel > 0.30:
				lines.append("[color=#FFB454]■[/color] [b][color=#E9EEF6]Inversions : %.2f s pour repartir du bon côté[/color][/b] — c'est là que tu perds tes points. Lis le rebond : les inversions arrivent souvent en bord de zone." % mdel)
			else:
				lines.append("[color=#7CE38B]■[/color] Bonne réactivité aux inversions (%.2f s en médiane)." % mdel)

# ============================================================
#  RÉSULTATS FINDER
# ============================================================
func _render_fres() -> void:
	mode = Mode.F_RESULTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud_root.visible = false
	var g := GameDB.get_game(game)
	var new_sens := sens * k_final

	res_game_lbl.text = "SENS RECOMMANDÉE · %s" % g["label"]
	res_sens_lbl.text = GameDB.fmt_sens(game, new_sens)
	res_range_lbl.text = "plage valide %s – %s · %+d%% vs actuelle" % [
		GameDB.fmt_sens(game, sens * k_lo), GameDB.fmt_sens(game, sens * k_hi),
		int(round((k_final - 1.0) * 100))]
	res_conf_lbl.text = confidence_txt

	# équivalents tous jeux
	for ch in res_equiv_box.get_children():
		ch.queue_free()
	res_equiv_box.add_child(UIKit.label("ÉQUIVALENTS", 11, UIKit.COL_MUTED, true))
	for gk in GameDB.keys():
		if gk == game:
			continue
		var eq := GameDB.convert_sens(new_sens, game, gk)
		res_equiv_box.add_child(UIKit.label("%-14s %s" % [GameDB.get_game(gk)["label"].to_lower(), GameDB.fmt_sens(gk, eq)], 13, UIKit.COL_TEXT, true))
	res_equiv_box.add_child(UIKit.label("eDPI %d · cm/360 %.1f" % [int(new_sens * dpi), GameDB.cm360(game, new_sens, dpi)], 13, UIKit.COL_ACCENT2, true))

	# table des rounds
	for ch in res_table.get_children():
		ch.queue_free()
	for h in ["ROUND", "TYPE", "SENS", "SCORE", "TP", "PRÉC.", "TRACK", "OVER/UNDER"]:
		res_table.add_child(UIKit.label(h, 10, UIKit.COL_MUTED, true))
	var best_score := 0.0
	for r in rounds:
		best_score = max(best_score, r["score"])
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		var col := UIKit.COL_TEXT if r["score"] == best_score else UIKit.COL_MUTED
		var err_txt := "±0"
		if r["err"] > 0.04:
			err_txt = "+%d%% over" % int(r["err"] * 100)
		elif r["err"] < -0.04:
			err_txt = "%d%% under" % int(r["err"] * 100)
		var cells := ["R%d" % (i + 1), r["stage"], GameDB.fmt_sens(game, sens * r["k"]),
			str(int(r["score"])), "%.2f" % r["tp"], "%d%%" % int(r["acc"] * 100),
			"%d%%" % int(r["trk_pct"] * 100), err_txt]
		for ctxt in cells:
			res_table.add_child(UIKit.label(ctxt, 11, col, true))

	# diagnostic
	var werr := 0.0
	for r in rounds:
		werr += r["err"]
	werr /= rounds.size()
	var lines: Array = []
	if werr > 0.07:
		lines.append("[b][color=#E9EEF6]Tendance overshoot[/color][/b] (+%d%%) : tes flicks dépassent la cible puis corrigent — sens probablement trop haute, la recommandation compense." % int(werr * 100))
	elif werr < -0.07:
		lines.append("[b][color=#E9EEF6]Tendance undershoot[/color][/b] (%d%%) : tes flicks s'arrêtent avant la cible — sens probablement trop basse, la recommandation compense." % int(werr * 100))
	else:
		lines.append("[b][color=#E9EEF6]Flicks nets[/color][/b] : dépassement moyen quasi nul sur la plage testée.")
	lines.append("Score par round = [b][color=#E9EEF6]throughput effectif ISO 9241-9[/color][/b] (IDe = log₂(Ae/We+1), We = 4,133·σ de tes impacts, ratés inclus) + tracking. Les premiers 20 %% de chaque round (adaptation à la sens) sont exclus, et l'effet d'apprentissage entre rounds est retiré (détrend).")
	lines.append("La courbe cyan est un [b][color=#E9EEF6]processus gaussien[/color][/b] (bande = incertitude ±1σ) ; la plage rouge = plateau du GP ∩ bootstrap de l'optimum (140 rééchantillonnages). L'optimum est une [b][color=#E9EEF6]plage[/color][/b], pas un point — les études NVIDIA montrent un large plateau.")
	lines.append("Joue [b][color=#E9EEF6]2–3 jours[/color][/b] avec la nouvelle sens avant de juger.")
	res_diag.text = "\n".join(lines)

	curve_ctl.setup(rounds, fres_scan, k_final, k_lo, k_hi, UIKit.mono())
	_show_only(fres_panel)
	_save_result(new_sens)
	_refresh_last_calib()

# ============================================================
#  SANDBOX
# ============================================================
func _start_sandbox() -> void:
	mode = Mode.SANDBOX
	paused = false
	k = k_final
	cur = {"hits": 0, "misses": 0, "tth": [], "errs": [], "sum_id": 0.0, "trk_on": 0.0, "trk_tot": 0.0}
	hud_root.visible = true
	hud_l1.text = "sandbox · sens recommandée"
	hud_timer.text = ""
	hud_hint.text = "Échap pour revenir aux résultats"
	_refresh_play_hud()
	_show_only(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	anchor_yaw = yaw
	_spawn_finder_target()

func _end_sandbox() -> void:
	_clear_targets()
	mode = Mode.F_RESULTS
	hud_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only(fres_panel)

# ============================================================
#  INPUT & BOUCLE
# ============================================================
func _input(event: InputEvent) -> void:
	if fire_wait >= 0:
		_capture_fire_bind(event)
		return
	var eb := _event_bind(event)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
		var g := GameDB.get_game(game)
		var deg_per_count: float = g["yaw"] * sens * k
		yaw -= event.relative.x * deg_per_count
		pitch -= event.relative.y * deg_per_count
		pitch = clamp(pitch, -89.0, 89.0)
		cam.rotation_degrees = Vector3(pitch, yaw, 0)
		if has_path:
			_record_path()
	elif eb != "" and fire_binds.has(eb):
		if paused:
			return
		if mode == Mode.F_FLICK or mode == Mode.SANDBOX or (mode == Mode.TRAIN and str(t_cfg.get("type", "")) == "click"):
			_shoot()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		match mode:
			Mode.COUNT:
				if room_active:
					_goto_menu()   # défi : le décompte est calé sur l'heure serveur, pas de pause
				else:
					_pause()        # solo : on met en pause sans perdre la run
			Mode.F_FLICK, Mode.F_TRACK, Mode.TRAIN:
				_pause()
			Mode.SANDBOX:
				_end_sandbox()
			Mode.R_VIEW:
				_rvw_close()
			Mode.F_RESULTS:
				_goto_menu()
			Mode.T_RESULTS:
				if setup_panel.visible:
					_setup_back()
				else:
					_goto_menu()
			Mode.MENU:
				if setup_panel.visible:
					_setup_back()
				elif pl_edit_panel.visible:
					_pl_cancel_editor()
				elif quit_panel.visible:
					quit_panel.visible = false
				else:
					quit_panel.visible = true

func _pause() -> void:
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# on ne relance pas un round de défi (calé sur l'heure serveur)
	pause_restart_btn.visible = not room_active
	if locate_snd != null:
		locate_snd.stop()
	_show_only(pause_panel)

# recommence l'activité en cours depuis le début (même mode, durée, paramètres)
func _restart_run() -> void:
	paused = false
	match mode:
		Mode.TRAIN:
			_start_train(t_mode)
		Mode.F_FLICK, Mode.F_TRACK:
			_start_finder(protocol)
		Mode.COUNT:
			if count_ctx == "finder":
				_start_finder(protocol)
			else:
				_start_train(t_mode)
		_:
			_resume()

func _resume() -> void:
	paused = false
	_show_only(count_panel if mode == Mode.COUNT else null)   # reprendre le décompte l'affiche à nouveau
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# relancer le ping SONAR si une cible sonore est en jeu
	if mode == Mode.TRAIN and bool(t_cfg.get("locate", false)) and not targets.is_empty():
		locate_snd.global_position = targets[0]["node"].position
		locate_snd.play()

var win_focused := true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		win_focused = false
		Engine.max_fps = fps_bg if fps_bg > 0 else fps_cap
		if (mode == Mode.F_FLICK or mode == Mode.F_TRACK or mode == Mode.TRAIN) and not paused:
			_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		win_focused = true
		Engine.max_fps = fps_cap

func _process(delta: float) -> void:
	match mode:
		Mode.MENU:
			# caméra d'ambiance derrière le menu
			yaw = wrapf(yaw + delta * 2.2, -180.0, 180.0)
			pitch = lerpf(pitch, 4.0, delta * 1.5)
			cam.rotation_degrees = Vector3(pitch, yaw, 0)
		Mode.COUNT:
			if paused:
				return
			count_timer -= delta
			cnt_num_lbl.text = str(int(ceil(max(count_timer, 0.01))))
			if count_timer <= 0.0:
				_show_only(null)
				if count_ctx == "finder":
					_start_flick_phase()
				else:
					_start_train_run()
				if not win_focused:
					_pause()
		Mode.F_FLICK, Mode.F_TRACK:
			if not paused:
				phase_timer -= delta
				hud_timer.text = "⏱ %4.1fs" % max(phase_timer, 0.0)
				if mode == Mode.F_TRACK:
					_update_track(delta)
				if phase_timer <= 0.0:
					if mode == Mode.F_FLICK:
						_clear_targets()
						_start_track_phase()
					else:
						_end_round()
		Mode.T_RESULTS, Mode.R_VIEW:
			_rp_update(delta)
		Mode.TRAIN:
			if not paused:
				phase_timer -= delta
				hud_timer.text = "⏱ %4.1fs" % max(phase_timer, 0.0)
				var m: Dictionary = t_cfg
				if m["type"] == "click":
					_update_click_targets(delta, m)
				else:
					_update_track(delta)
					_refresh_play_hud()
				var tt := _train_t()
				if tt - rec_last_t >= 0.005:
					rec_samples.append(Vector3(tt, yaw, pitch))
					rec_last_t = tt
				if phase_timer <= 0.0:
					_end_train()

func _refresh_finder_hud() -> void:
	hud_l2.text = "cibles %d" % cur["hits"]
	var tot: int = cur["hits"] + cur["misses"]
	hud_l3.text = ("précision %d%%" % int(float(cur["hits"]) / tot * 100)) if tot > 0 else "précision —"

func _refresh_play_hud() -> void:
	if cur.is_empty():
		return
	if mode == Mode.TRAIN:
		var m: Dictionary = t_cfg
		if m["type"] == "click":
			hud_l2.text = "score %d · combo %d" % [t_score, t_combo]
			var tot: int = cur["hits"] + cur["misses"]
			hud_l3.text = ("précision %d%%" % int(float(cur["hits"]) / tot * 100)) if tot > 0 else "précision —"
		else:
			hud_l2.text = "score %d" % t_score
			var pct := 0.0
			if cur["trk_tot"] > 0.0:
				pct = cur["trk_on"] / cur["trk_tot"] * 100.0
			hud_l3.text = "sur cible %d%%" % int(pct)
	else:
		_refresh_finder_hud()

# ============================================================
#  PRÉFÉRENCES / RECORDS
# ============================================================
var _cfg: ConfigFile

func _cfg_ref() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load("user://senslab.cfg")
	return _cfg

func _prefs_get(key: String, def):
	return _cfg_ref().get_value("prefs", key, def)

func _prefs_set(key: String, val) -> void:
	_cfg_ref().set_value("prefs", key, val)
	_cfg_ref().save("user://senslab.cfg")

func _load_prefs() -> void:
	game = _prefs_get("game", "valorant")
	if GameDB.keys().find(game) < 0:
		game = "valorant"
	_refresh_game_btns()
	pseudo = str(_prefs_get("pseudo", ""))
	in_pseudo.text = pseudo
	in_dpi.text = str(_prefs_get("dpi", 800))
	_load_game_inputs()
	_set_duration(int(_prefs_get("duration", 60)))
	# affichage / performances / tir
	fps_cap = int(_prefs_get("fps_cap", 400))
	fps_bg = int(_prefs_get("fps_bg", 30))
	disp_size_opt.select(clampi(int(_prefs_get("win_mode", 0)), 0, WIN_MODES.size() - 1))
	disp_screen_opt.select(clampi(int(_prefs_get("screen", 0)), 0, disp_screen_opt.item_count - 1))
	disp_fps_opt.select(maxi(FPS_CAPS.find(fps_cap), 0))
	disp_fpsbg_opt.select(maxi(FPS_BG.find(fps_bg), 0))
	fire_binds = [str(_prefs_get("fire1", "mouse:1")), str(_prefs_get("fire2", ""))]
	if fire_binds[0] == "" and fire_binds[1] == "":
		fire_binds[0] = "mouse:1"
	_refresh_fire_btns()
	# son, qualité, viseur
	var vol := float(_prefs_get("vol", 100))
	vol_slider.set_value_no_signal(vol)
	_apply_volume(vol)
	vsync_opt.select(clampi(int(_prefs_get("vsync", 0)), 0, 1))
	msaa_opt.select(clampi(int(_prefs_get("msaa", 2)), 0, 2))
	rscale_opt.select(clampi(int(_prefs_get("rscale", 0)), 0, RSCALES.size() - 1))
	ch_col_pick.color = Color(str(_prefs_get("ch_col_hex", "E9EEF6")))
	bg_col_pick.color = Color(str(_prefs_get("bg_hex", "0B0F17")))
	grid_base_pick.color = Color(str(_prefs_get("grid_base_hex", "0B0F15")))
	grid_line_pick.color = Color(str(_prefs_get("grid_line_hex", "1A475C")))
	pop_opt.select(clampi(int(_prefs_get("pop_fx", 0)), 0, 1))
	glow_opt.select(clampi(int(_prefs_get("glow", 1)), 0, 1))
	# son de tir personnalisé (si un fichier a été choisi)
	var snd_path := str(_prefs_get("hit_sound", ""))
	if snd_path != "" and _load_hit_sound(snd_path):
		custom_snd_lbl.text = "son perso : %s" % snd_path.get_file()
	else:
		custom_snd_lbl.text = "son par défaut"
	_apply_quality()
	_apply_crosshair()
	_apply_bg()
	_apply_grid()
	_apply_fx()
	_apply_glow()
	_apply_display()
	_refresh_derived()

func _save_prefs() -> void:
	var c := _cfg_ref()
	c.set_value("prefs", "game", game)
	c.set_value("prefs", "dpi", dpi)
	c.set_value("prefs", "duration", t_dur)
	c.save("user://senslab.cfg")

func _get_record(mk: String, dur: int) -> int:
	return int(_cfg_ref().get_value("records", "%s_%d" % [mk, dur], 0))

func _set_record(mk: String, dur: int, score: int) -> void:
	_cfg_ref().set_value("records", "%s_%d" % [mk, dur], score)
	_cfg_ref().save("user://senslab.cfg")

func _save_result(new_sens: float) -> void:
	var c := _cfg_ref()
	var g := GameDB.get_game(game)
	c.set_value("results", "last", {
		"label": g["label"], "sens": GameDB.fmt_sens(game, new_sens),
		"lo": GameDB.fmt_sens(game, sens * k_lo), "hi": GameDB.fmt_sens(game, sens * k_hi)})
	var hist: Array = c.get_value("results", "history", [])
	hist.append({"game": game, "sens": new_sens, "k": k_final, "dpi": dpi, "protocol": protocol})
	c.set_value("results", "history", hist)
	c.save("user://senslab.cfg")

# ============================================================
#  CONTROLS PERSONNALISÉS
# ============================================================
class IconDraw extends Control:
	var kind := ""
	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(56, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size / 2.0
		var acc := Color("FF4655")
		var cy := Color("57D4FF")
		var mu := Color("46536B")
		match kind:
			"grid":
				draw_circle(c + Vector2(-14, 9), 7, acc)
				draw_circle(c + Vector2(2, -10), 7, acc)
				draw_circle(c + Vector2(17, 10), 7, acc)
			"micro":
				draw_arc(c, 14, 0, TAU, 32, mu, 1.5)
				draw_circle(c, 4.5, acc)
				for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					draw_line(c + d * 9.0, c + d * 17.0, cy, 2.0)
			"flick":
				draw_arc(c + Vector2(-12, 10), 5, 0, TAU, 24, mu, 2.0)
				draw_line(c + Vector2(-8, 6), c + Vector2(9, -6), cy, 2.0)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(15, -10), c + Vector2(4, -8), c + Vector2(11, 0)]), cy)
				draw_circle(c + Vector2(15, -10), 7, acc)
			"head":
				draw_line(c + Vector2(-21, 6), c + Vector2(21, 6), mu, 2.0)
				for x in [-13.0, 1.0, 15.0]:
					draw_circle(c + Vector2(x, 0), 5, acc)
			"strafe":
				draw_circle(c, 8, acc)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-23, 0), c + Vector2(-14, -6), c + Vector2(-14, 6)]), cy)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(23, 0), c + Vector2(14, -6), c + Vector2(14, 6)]), cy)
			"react":
				draw_polyline(PackedVector2Array([
					c + Vector2(-20, 10), c + Vector2(-8, -8), c + Vector2(4, 10), c + Vector2(16, -8)]), cy, 2.0)
				draw_circle(c + Vector2(16, -8), 5.5, acc)
			"spider":
				draw_circle(c, 11, acc)
				draw_arc(c, 17, 0, TAU, 40, cy, 2.0)
			"dot":
				draw_arc(c, 15, 0, TAU, 40, mu, 1.5)
				draw_arc(c, 8, 0, TAU, 32, mu, 1.5)
				draw_circle(c, 2.6, acc)
			"six":
				draw_circle(c + Vector2(-17, -4), 6, acc)
				draw_circle(c + Vector2(17, 8), 6, acc)
				draw_line(c + Vector2(-10, -2), c + Vector2(10, 6), cy, 2.0)
			"vert":
				draw_circle(c, 7, acc)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -23), c + Vector2(-6, -14), c + Vector2(6, -14)]), cy)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, 23), c + Vector2(-6, 14), c + Vector2(6, 14)]), cy)
			"orbit":
				draw_arc(c, 16, 0.4, TAU + 0.4, 48, cy, 2.0)
				draw_circle(c + Vector2(16, 0).rotated(0.4), 5.5, acc)
				draw_circle(c, 3.0, mu)
			"reflex":
				draw_arc(c, 16, 0, TAU, 40, mu, 1.5)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(3, -14), c + Vector2(-7, 2), c + Vector2(-1, 2),
					c + Vector2(-3, 14), c + Vector2(7, -2), c + Vector2(1, -2)]), cy)
				draw_circle(c + Vector2(10, -10), 3.5, acc)
			"rapide", "standard", "precision":
				var nn := 1
				if kind == "standard":
					nn = 2
				elif kind == "precision":
					nn = 3
				draw_arc(c, 17, 0, TAU, 40, mu, 2.0)
				draw_line(c + Vector2(0, -17), c + Vector2(0, -22), mu, 2.0)
				draw_line(c, c + Vector2(7, -9), acc, 2.0)
				for i in nn:
					draw_circle(c + Vector2((i - (nn - 1) / 2.0) * 10.0, 9.0), 3.2, cy)

# viseur paramétrable façon Valorant : point central + 4 lignes, chacun réglable
# indépendamment (taille, épaisseur, écart au centre, contour).
class CrossDraw extends Control:
	var flash := 0.0
	var preview := false        # true = aperçu réglages (dessine hors capture souris)
	var ch_col := Color("E9EEF6")
	var ch_dot := false
	var ch_dot_size := 2.0
	var ch_lines := true
	var ch_len := 7.0
	var ch_thick := 2.0
	var ch_gap := 4.0
	var ch_outline := false
	var ch_flash := true        # change de couleur brièvement au tir réussi
	func flash_hit() -> void:
		if not ch_flash:
			return
		flash = 1.0
		queue_redraw()
	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = max(0.0, flash - delta * 6.0)
		if preview or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			queue_redraw()
	func _draw() -> void:
		if not preview and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var c := (size / 2.0).round()
		var col := ch_col.lerp(Color("7CE38B"), flash) if ch_flash else ch_col
		var out := Color(0.0, 0.0, 0.0, col.a)
		if ch_lines and ch_len > 0.0:
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var a: Vector2 = c + d * ch_gap
				var b: Vector2 = c + d * (ch_gap + ch_len)
				if ch_outline:
					draw_line(a, b, out, ch_thick + 2.0)
				draw_line(a, b, col, ch_thick)
		if ch_dot and ch_dot_size > 0.0:
			if ch_outline:
				draw_circle(c, ch_dot_size + 1.0, out)
			draw_circle(c, ch_dot_size, col)

# barre de navigation du replay : progression, marqueurs de clics, scrub à la souris
class TimelineDraw extends Control:
	var dur := 60.0
	var tcur := 0.0
	var clicks: Array = []
	var on_seek: Callable
	var scrubbing := false

	func _process(_d: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			scrubbing = ev.pressed
			if ev.pressed:
				_seek(ev.position.x)
		elif ev is InputEventMouseMotion and scrubbing:
			_seek(ev.position.x)

	func _seek(px: float) -> void:
		if on_seek.is_valid():
			on_seek.call(clampf((px - 8.0) / maxf(size.x - 16.0, 1.0), 0.0, 1.0) * dur)

	func _draw() -> void:
		var ty := size.y * 0.5
		var w := size.x - 16.0
		var d := maxf(dur, 0.1)
		draw_line(Vector2(8, ty), Vector2(size.x - 8, ty), Color("232D3F"), 5.0)
		for c in clicks:
			var x: float = 8.0 + w * c["t"] / d
			var colt := Color("7CE38B") if c["hit"] else (Color("FFB454") if c["early"] else Color("FF4655"))
			draw_line(Vector2(x, ty - 6), Vector2(x, ty + 6), colt, 1.4)
		draw_line(Vector2(8, ty), Vector2(8 + w * tcur / d, ty), Color("FF4655"), 5.0)
		draw_circle(Vector2(8 + w * tcur / d, ty), 7.0, Color("E9EEF6"))
		draw_string(UIKit.mono(), Vector2(size.x - 108, ty - 10), "%5.1f / %.0f s" % [tcur, d],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7B8798"))

# surcouche du replay première personne : traînée du viseur projetée dans la vue
# 3D courante + marqueurs de clics, colorés selon le défaut
class ReplayOverlay extends Control:
	var m: Node3D
	var track := false

	func _init(mm: Node3D) -> void:
		m = mm
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		if m.rec_samples.is_empty():
			return
		var cam: Camera3D = m.cam
		# croix centrale : le viseur du joueur pendant le replay
		var ctr := size / 2.0
		for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(ctr + dv * 4.0, ctr + dv * 11.0, Color("E9EEF6"), 2.0)
		# traînée du viseur (1,2 s) projetée dans la vue
		var i1: int = m._rp_idx(m.rp_t)
		var i0: int = m._rp_idx(maxf(m.rp_t - 1.2, 0.0))
		var prev := Vector2.ZERO
		var prev_ok := false
		for i in range(i0, i1 + 1):
			var s: Vector3 = m.rec_samples[i]
			var world: Vector3 = cam.position + m._dir_from_angles(s.y, s.z) * 10.0
			if cam.is_position_behind(world):
				prev_ok = false
				continue
			var pt: Vector2 = cam.unproject_position(world)
			if prev_ok:
				var col: Color
				match m.rp_cls[i]:
					1: col = Color("7CE38B")
					2: col = Color("FF4655") if track else Color("FFB454")
					_: col = Color("57D4FF")
				col.a = clampf(1.0 - (m.rp_t - s.x) / 1.2, 0.0, 1.0)
				draw_line(prev, pt, col, 2.4)
			prev = pt
			prev_ok = true
		# marqueurs de clics récents
		for c in m.rec_clicks:
			if c["t"] > m.rp_t or m.rp_t - c["t"] > 0.7:
				continue
			var world2: Vector3 = cam.position + m._dir_from_angles(c["ang"].x, c["ang"].y) * 10.0
			if cam.is_position_behind(world2):
				continue
			var p: Vector2 = cam.unproject_position(world2)
			var fade: float = 1.0 - (m.rp_t - c["t"]) / 0.7
			if c["hit"]:
				var g := Color("7CE38B")
				g.a = fade
				draw_arc(p, 9.0, 0, TAU, 24, g, 2.2)
			else:
				var x: Color = Color("FFB454") if c["early"] else Color("FF4655")
				x.a = fade
				draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), x, 2.4)
				draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), x, 2.4)

class CurveDraw extends Control:
	var rounds: Array = []
	var scan := {}
	var k_final := 1.0
	var k_lo := 1.0
	var k_hi := 1.0
	var mono: Font
	func setup(r: Array, s: Dictionary, kf: float, lo: float, hi: float, fm: Font) -> void:
		rounds = r
		scan = s
		k_final = kf
		k_lo = lo
		k_hi = hi
		mono = fm
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0E131C"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("232D3F"), false, 1.0)
		if rounds.is_empty():
			return
		var pad_l := 56.0; var pad_r := 20.0; var pad_t := 22.0; var pad_b := 32.0
		var ln_min: float = log(0.60)
		var ln_max: float = log(1.48)
		var y_min := 1e9; var y_max := -1e9
		for r in rounds:
			y_min = min(y_min, r["score"])
			y_max = max(y_max, r["score"])
		if not scan.is_empty():
			var mus: PackedFloat32Array = scan["mus"]
			var sds2: PackedFloat32Array = scan["sds"]
			for i in mus.size():
				y_min = min(y_min, mus[i] - sds2[i])
				y_max = max(y_max, mus[i] + sds2[i])
		y_min = max(0.0, y_min - 10.0)
		y_max = min(175.0, y_max + 10.0)
		var fx := func(kk: float) -> float:
			return pad_l + (log(kk) - ln_min) / (ln_max - ln_min) * (size.x - pad_l - pad_r)
		var fy := func(s: float) -> float:
			return pad_t + (1.0 - (s - y_min) / (y_max - y_min)) * (size.y - pad_t - pad_b)
		# bande de plage valide
		var xlo: float = fx.call(k_lo)
		var xhi: float = fx.call(k_hi)
		draw_rect(Rect2(Vector2(xlo, pad_t), Vector2(xhi - xlo, size.y - pad_t - pad_b)), Color(1.0, 0.28, 0.33, 0.10))
		# grille
		for kk in [0.66, 0.8, 1.0, 1.2, 1.4]:
			var x: float = fx.call(kk)
			draw_line(Vector2(x, pad_t), Vector2(x, size.y - pad_b), Color("232D3F"), 1.0)
			draw_string(mono, Vector2(x - 16, size.y - 10), "×%.2f" % kk, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("7B8798"))
		# processus gaussien : bande ±1σ puis moyenne a posteriori
		if not scan.is_empty():
			var kss: PackedFloat32Array = scan["ks"]
			var mus2: PackedFloat32Array = scan["mus"]
			var sds3: PackedFloat32Array = scan["sds"]
			var band := PackedVector2Array()
			for i in kss.size():
				band.append(Vector2(fx.call(kss[i]),
					clamp(fy.call(mus2[i] + sds3[i]), pad_t, size.y - pad_b)))
			for i in range(kss.size() - 1, -1, -1):
				band.append(Vector2(fx.call(kss[i]),
					clamp(fy.call(mus2[i] - sds3[i]), pad_t, size.y - pad_b)))
			if band.size() >= 3:
				draw_colored_polygon(band, Color(0.34, 0.83, 1.0, 0.09))
			var prev := Vector2.ZERO
			for i in kss.size():
				var pt := Vector2(fx.call(kss[i]),
					clamp(fy.call(mus2[i]), pad_t, size.y - pad_b))
				if i > 0:
					draw_line(prev, pt, Color("57D4FF"), 2.0)
				prev = pt
		# k final
		var xf: float = fx.call(k_final)
		draw_dashed_line(Vector2(xf, pad_t), Vector2(xf, size.y - pad_b), Color("FF4655"), 2.0, 6.0)
		draw_string(mono, Vector2(xf - 22, pad_t - 6), "ta sens", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("FF4655"))
		# points (confirm en rouge, refine en cyan)
		for r in rounds:
			var col := Color("E9EEF6")
			if r["stage"] == "confirm":
				col = Color("FF4655")
			elif r["stage"] == "refine":
				col = Color("57D4FF")
			draw_circle(Vector2(fx.call(r["k"]), fy.call(r["score"])), 5.0, col)
