extends Node3D
# ============================================================
#  SENS LAB — trainer d'aim + calibrateur de sensibilité
#  Valorant · CS2 · Overwatch 2 · Apex · COD
#  Sens angulaire exacte : degrés/count = yaw_jeu × sens × k
# ============================================================

const HEYE := 1.6
const R_DIST := 10.0
const TP_REF := 2.4          # bits/s de référence pour normaliser le débit de Fitts

enum Mode { MENU, COUNT, F_FLICK, F_TRACK, TRAIN, F_RESULTS, T_RESULTS, SANDBOX }

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
	"grid": {"name": "GRIDSHOT", "desc": "3 cibles simultanées · vitesse brute", "icon": "grid",
		"pack": "vitesse", "diff": 1, "type": "click",
		"simul": 3, "r": 0.45, "cone": 26.0, "p_lo": -2.0, "p_hi": 16.0, "anchored": true},
	"spider": {"name": "SPIDER", "desc": "une grosse cible à la fois · enchaîne sans t'arrêter", "icon": "spider",
		"pack": "vitesse", "diff": 2, "type": "click",
		"simul": 1, "r": 0.42, "cone": 22.0, "p_lo": -2.0, "p_hi": 14.0, "anchored": true},
	"grid5": {"name": "GRIDSHOT ULTRA", "desc": "5 cibles simultanées · plus petites, plus larges", "icon": "grid",
		"pack": "vitesse", "diff": 3, "type": "click",
		"simul": 5, "r": 0.36, "cone": 32.0, "p_lo": -3.0, "p_hi": 17.0, "anchored": true},
	"hyper": {"name": "HYPERGRID", "desc": "4 petites cibles · zone immense, cadence max", "icon": "grid",
		"pack": "vitesse", "diff": 5, "type": "click",
		"simul": 4, "r": 0.28, "cone": 36.0, "p_lo": -5.0, "p_hi": 19.0, "anchored": true},
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
}
const MODE_ORDER := [
	"grid", "spider", "grid5", "hyper",
	"micro", "head", "long", "headmicro", "dot",
	"flick", "wide", "six", "headflick", "multi",
	"strafe", "microtrk", "react", "vert", "air", "turbo",
	"reflex", "dodge", "headrush", "reflexmicro", "dodgemicro",
]
const DURATIONS := [30, 60, 120]

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
var confidence_txt := ""

# entraînement
var t_mode := "grid"
var t_dur := 60
var t_score := 0
var t_combo := 0
var t_best_streak := 0

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

# ---------- UI ----------
var ui: CanvasLayer
var crosshair: Control
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

# ============================================================
func _ready() -> void:
	randomize()
	Engine.max_fps = 400
	Input.use_accumulated_input = false
	lb = Leaderboard.new()
	add_child(lb)
	lb.top_received.connect(_on_lb_top)
	lb.submitted.connect(_on_lb_submitted)
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
	upd.progress.connect(_on_update_progress)
	upd.failed.connect(_on_update_failed)
	_build_world()
	_build_sounds()
	_build_ui()
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
void fragment() {
	vec2 uv = UV * tiles;
	vec2 g = abs(fract(uv) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.06, min(g.x, g.y));
	vec3 base = vec3(0.045, 0.058, 0.082);
	vec3 lc = vec3(0.10, 0.28, 0.36);
	ALBEDO = mix(base, lc, line * 0.4);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tiles", tiles)
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	return mi

# ============================================================
#  SONS
# ============================================================
func _build_sounds() -> void:
	snd_hit = _beep_player(880.0, 0.07, 0.35, 1320.0)
	snd_miss = _beep_player(190.0, 0.05, 0.30, 0.0)
	snd_round = _beep_player(520.0, 0.16, 0.30, 780.0)

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
	for entry in [["train", "ENTRAÎNEMENT"], ["duel", "DÉFI 1V1VX"], ["finder", "SENS FINDER"], ["board", "CLASSEMENT"], ["settings", "RÉGLAGES"]]:
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
	tab_panels["duel"] = _build_tab_duel()
	tab_panels["finder"] = _build_tab_finder()
	tab_panels["board"] = _build_tab_board()
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
			c["btn"].pressed.connect(_start_train.bind(mk))
			mode_rec_lbls[mk] = c["extra"]
			grid.add_child(c["btn"])
		packs_v.add_child(grid)
	return v

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
	var intro := UIKit.label("Calibration à l'aveugle : chaque round modifie ta sensibilité sans te le dire. Le moteur mesure ton débit de Fitts (bits/s), ton tracking et tes dépassements de cible, ajuste ta courbe de performance et en déduit ta sens optimale — avec les équivalents pour les 5 jeux.", 13, UIKit.COL_MUTED)
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
	v.add_child(mrow)

	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	for d in DURATIONS:
		var db := UIKit.btn("%d s" % d, false, 12)
		db.pressed.connect(_lb_set_dur.bind(d))
		lb_dur_btns.append(db)
		drow.add_child(db)
	v.add_child(drow)

	lb_status = UIKit.label("", 12, UIKit.COL_MUTED, true)
	v.add_child(lb_status)

	lb_grid = GridContainer.new()
	lb_grid.columns = 3
	lb_grid.add_theme_constant_override("h_separation", 30)
	lb_grid.add_theme_constant_override("v_separation", 4)
	v.add_child(lb_grid)
	return v

func _lb_set_dur(d: int) -> void:
	lb_dur = d
	_lb_refresh()

func _lb_refresh() -> void:
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
	lb.fetch_top(lb_mode, lb_dur)

func _on_lb_top(ok: bool, rows: Array) -> void:
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
		_fill_lb_grid(dash_lb_grid, rows, 10)

func _fill_lb_grid(grid: GridContainer, rows: Array, limit: int) -> void:
	for h in ["#", "PSEUDO", "SCORE"]:
		grid.add_child(UIKit.label(h, 11, UIKit.COL_MUTED, true))
	for i in mini(rows.size(), limit):
		var r: Dictionary = rows[i]
		var me: bool = str(r.get("player", "")) == pseudo and pseudo != ""
		var col := UIKit.COL_ACCENT2 if me else (UIKit.COL_TEXT if i < 3 else UIKit.COL_MUTED)
		grid.add_child(UIKit.label("%d" % (i + 1), 13, col, true))
		grid.add_child(UIKit.label(str(r.get("player", "?")), 13, col, true))
		grid.add_child(UIKit.label(str(int(r.get("score", 0))), 13, col, true))

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
	return v

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
	go.pressed.connect(func(): _start_train(MODE_ORDER[dash_mode_opt.selected]))
	chain.add_child(go)
	right.add_child(chain)
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
	for p in [menu_panel, count_panel, pause_panel, fres_panel, tres_panel]:
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
		"tth": [], "errs": [], "sum_id": 0.0, "trk_on": 0.0, "trk_tot": 0.0}
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
	_refresh_finder_hud()
	_spawn_finder_target()

func _start_track_phase() -> void:
	mode = Mode.F_TRACK
	phase_timer = PROTOCOLS[protocol]["track"]
	hud_hint.text = "garde le viseur sur la cible"
	_clear_targets()
	_spawn_tracker(MODES["strafe"]["trk"])

func _end_round() -> void:
	snd_round.play()
	trk_active = false
	_clear_targets()
	var p: Dictionary = PROTOCOLS[protocol]
	var acc := 0.0
	var tot: int = cur["hits"] + cur["misses"]
	if tot > 0:
		acc = float(cur["hits"]) / tot
	# débit de Fitts effectif (bits/s) : Σ ID / durée de phase
	var tp: float = cur["sum_id"] / float(p["flick"])
	var flick_norm: float = clamp(tp / TP_REF, 0.0, 1.0) * (0.55 + 0.45 * acc)
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
		"err": err, "kills": cur["hits"]})
	round_i += 1

	var n_base: int = p["base"].size()
	var n_refine: int = p["refine"]
	if rounds.size() == n_base and n_refine > 0:
		var kp := _fit_kopt()
		plan.append({"k": clamp(kp * 0.92, Analysis.K_MIN, Analysis.K_MAX), "stage": "refine"})
		plan.append({"k": clamp(kp * 1.09, Analysis.K_MIN, Analysis.K_MAX), "stage": "refine"})
	elif rounds.size() == n_base + n_refine:
		var kp2 := _fit_kopt()
		for i in p["confirm"]:
			plan.append({"k": kp2, "stage": "confirm"})
	if round_i >= plan.size():
		_finalise()
	else:
		_begin_round()

func _fit_kopt() -> float:
	var xs: Array = []; var ys: Array = []; var ws: Array = []; var ks: Array = []
	for r in rounds:
		xs.append(log(r["k"])); ys.append(r["score"])
		ws.append(float(max(1, r["kills"]))); ks.append(r["k"])
	fit = Analysis.wfit(xs, ys, ws)
	var kk := Analysis.kopt_from(fit, ks, ys)
	# correction over/undershoot (pondérée par kills)
	var werr := 0.0
	var wsum := 0.0
	for r in rounds:
		werr += r["err"] * max(1, r["kills"])
		wsum += max(1, r["kills"])
	if wsum > 0.0:
		werr /= wsum
	if werr > 0.07:
		kk *= 0.94
	elif werr < -0.07:
		kk *= 1.06
	return clamp(kk, Analysis.K_MIN, Analysis.K_MAX)

func _finalise() -> void:
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
	# plage recommandée : dispersion leave-one-out (l'optimum est une plage, pas un point)
	var ks: Array = []; var ys: Array = []; var ws: Array = []
	for r in rounds:
		ks.append(r["k"]); ys.append(r["score"]); ws.append(float(max(1, r["kills"])))
	var spread := Analysis.loo_spread(ks, ys, ws)
	var half: float = clamp(max(0.04, spread * 0.5), 0.04, 0.15)
	k_lo = k_final * (1.0 - half)
	k_hi = k_final * (1.0 + half)
	if confirm_ok and fit["r2"] >= 0.5 and spread <= 0.12:
		confidence_txt = "confiance élevée (R² %.2f)" % fit["r2"]
	elif confirm_ok or fit["r2"] >= 0.3:
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
	var off := randf_range(8.0, 32.0) * (1.0 if randf() < 0.5 else -1.0)
	var t_yaw := yaw + off
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
	_pop_fx(hit_t["node"].position, max(0.16, hit_t["r_ang"] / 57.3 * R_DIST))
	crosshair.flash_hit()
	if mode == Mode.F_FLICK:
		cur["hits"] += 1
		cur["tth"].append(tth)
		cur["sum_id"] += fitts_id
		cur["errs"].append(_ballistic_err())
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
		var m: Dictionary = MODES[t_mode]
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
	var m: Dictionary = MODES[mk]
	cnt_round_lbl.text = "%s · %d S" % [m["name"], t_dur]
	cnt_score_lbl.text = m["desc"]
	hud_l1.text = "%s · %ds" % [m["name"].to_lower(), t_dur]
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
	var m: Dictionary = MODES[t_mode]
	if m["type"] == "click":
		anchor_yaw = yaw
		hud_hint.text = "clique les cibles avant qu'elles expirent" if m.get("ttl", 0.0) > 0.0 else "clique les cibles"
		for i in int(m.get("simul", 1)):
			_spawn_train_target()
	else:
		hud_hint.text = "garde le viseur sur la cible"
		_spawn_tracker(m["trk"])
	_refresh_play_hud()

func _spawn_train_target() -> void:
	var m: Dictionary = MODES[t_mode]
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

func _end_train() -> void:
	snd_round.play()
	trk_active = false
	_clear_targets()
	var m: Dictionary = MODES[t_mode]
	var rec := _get_record(t_mode, t_dur)
	var new_rec := t_score > rec
	if new_rec:
		_set_record(t_mode, t_dur, t_score)
	tres_title.text = "%s · %d S" % [m["name"], t_dur]
	tres_score.text = str(t_score)
	if new_rec:
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
		_chip("RECORD", str(maxi(t_score, rec)), UIKit.COL_ACCENT2)
		_chip("PRÉCÉDENT MEILLEUR", str(rec) if rec > 0 else "—", UIKit.COL_TEXT)
		_chip("PRÉCISION", "%.1f%%" % acc, UIKit.COL_TEXT)
		_chip("COUPS/TIRS", "%d/%d" % [cur["hits"], tot], UIKit.COL_TEXT)
		_chip("CIBLES TUÉES", str(cur["hits"]), UIKit.COL_TEXT)
		_chip("SÉRIE MAX", str(t_best_streak), UIKit.COL_TEXT)
	else:
		var pct: float = (cur["trk_on"] / cur["trk_tot"] * 100.0) if cur["trk_tot"] > 0.0 else 0.0
		_chip("RECORD", str(maxi(t_score, rec)), UIKit.COL_ACCENT2)
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
	# envoi au classement puis rafraîchissement du top de cet exercice
	lb_mode = t_mode
	lb_dur = t_dur
	for ch in dash_lb_grid.get_children():
		ch.queue_free()
	if not lb.configured():
		tres_net.text = ""
		dash_lb_status.text = "classement en ligne non configuré"
	elif pseudo == "":
		tres_net.text = "pas de pseudo → score non envoyé au classement (RÉGLAGES)"
		dash_lb_status.text = "chargement…"
		lb.fetch_top(t_mode, t_dur)
	else:
		tres_net.text = "envoi au classement…"
		dash_lb_status.text = "envoi du score…"
		lb.submit(pseudo, t_mode, t_dur, t_score)
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
	var mm: Dictionary = MODES[t_mode]
	if mm["type"] == "click":
		for idx in rec_targets.size():
			var rt: Dictionary = rec_targets[idx]
			var t1: float = rt["t1"] if rt["t1"] >= 0.0 else rp_dur
			var alive: bool = rt["t0"] <= rp_t and rp_t <= t1
			if alive:
				if not rp_nodes.has(idx):
					rp_nodes[idx] = _make_sphere(mm["r"], UIKit.COL_ACCENT)
					add_child(rp_nodes[idx])
				var c := _rec_center(rt, rp_t)
				rp_nodes[idx].position = cam.position + _dir_from_angles(c.x, c.y) * R_DIST
			elif rp_nodes.has(idx):
				var n: MeshInstance3D = rp_nodes[idx]
				if rp_t > t1 and rp_t - t1 < 0.4:
					_pop_fx(n.position, mm["r"],
						UIKit.COL_OK if rt["fate"] == "hit" else Color(1.0, 0.28, 0.33, 0.8))
				n.queue_free()
				rp_nodes.erase(idx)
	elif not rec_tgt.is_empty():
		# cible de tracking : cyan quand tu étais dessus, rouge sinon
		if rp_trk_node == null or not is_instance_valid(rp_trk_node):
			rp_trk_node = _make_sphere(mm["trk"].get("r", 0.33), UIKit.COL_ACCENT)
			add_child(rp_trk_node)
		var j := _rp_tgt_idx(rp_t)
		rp_trk_node.position = cam.position + _dir_from_angles(rec_tgt[j].y, rec_tgt[j].z) * R_DIST
		var on: bool = j < rec_on.size() and bool(rec_on[j])
		var mat: StandardMaterial3D = rp_trk_node.material_override
		mat.emission = UIKit.COL_ACCENT2 if on else UIKit.COL_ACCENT
		mat.albedo_color = UIKit.COL_ACCENT2 if on else UIKit.COL_ACCENT
	rp_time_ctl.tcur = rp_t

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
	lines.append("Le score par round = débit de Fitts (bits/s, normalise distance et taille des cibles, ISO 9241-9) pondéré par la précision + tracking. L'optimum est une [b][color=#E9EEF6]plage[/color][/b], pas un point : toute sens dans la plage affichée est valide.")
	lines.append("Joue [b][color=#E9EEF6]2–3 jours[/color][/b] avec la nouvelle sens avant de juger.")
	res_diag.text = "\n".join(lines)

	curve_ctl.setup(rounds, fit, k_final, k_lo, k_hi, UIKit.mono())
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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
		var g := GameDB.get_game(game)
		var deg_per_count: float = g["yaw"] * sens * k
		yaw -= event.relative.x * deg_per_count
		pitch -= event.relative.y * deg_per_count
		pitch = clamp(pitch, -89.0, 89.0)
		cam.rotation_degrees = Vector3(pitch, yaw, 0)
		if has_path:
			_record_path()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if paused:
			return
		if mode == Mode.F_FLICK or mode == Mode.SANDBOX or (mode == Mode.TRAIN and MODES[t_mode]["type"] == "click"):
			_shoot()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		match mode:
			Mode.COUNT:
				_goto_menu()
			Mode.F_FLICK, Mode.F_TRACK, Mode.TRAIN:
				_pause()
			Mode.SANDBOX:
				_end_sandbox()
			Mode.F_RESULTS, Mode.T_RESULTS:
				_goto_menu()
			Mode.MENU:
				get_tree().quit()

func _pause() -> void:
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_only(pause_panel)

func _resume() -> void:
	paused = false
	_show_only(null)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

var win_focused := true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		win_focused = false
		if (mode == Mode.F_FLICK or mode == Mode.F_TRACK or mode == Mode.TRAIN) and not paused:
			_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		win_focused = true

func _process(delta: float) -> void:
	match mode:
		Mode.MENU:
			# caméra d'ambiance derrière le menu
			yaw = wrapf(yaw + delta * 2.2, -180.0, 180.0)
			pitch = lerpf(pitch, 4.0, delta * 1.5)
			cam.rotation_degrees = Vector3(pitch, yaw, 0)
		Mode.COUNT:
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
		Mode.T_RESULTS:
			_rp_update(delta)
		Mode.TRAIN:
			if not paused:
				phase_timer -= delta
				hud_timer.text = "⏱ %4.1fs" % max(phase_timer, 0.0)
				var m: Dictionary = MODES[t_mode]
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
		var m: Dictionary = MODES[t_mode]
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

class CrossDraw extends Control:
	var flash := 0.0
	func flash_hit() -> void:
		flash = 1.0
		queue_redraw()
	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = max(0.0, flash - delta * 6.0)
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			queue_redraw()
	func _draw() -> void:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var c := size / 2.0
		var col := Color("E9EEF6").lerp(Color("7CE38B"), flash)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(c + d * 4.0, c + d * 11.0, col, 2.0)

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
	var fit := {}
	var k_final := 1.0
	var k_lo := 1.0
	var k_hi := 1.0
	var mono: Font
	func setup(r: Array, f: Dictionary, kf: float, lo: float, hi: float, fm: Font) -> void:
		rounds = r
		fit = f
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
		y_min = max(0.0, y_min - 12.0)
		y_max = min(108.0, y_max + 12.0)
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
		# parabole
		if fit.get("a", 0.0) < -1e-4:
			var prev := Vector2.ZERO
			for i in 121:
				var kk2: float = exp(ln_min + (ln_max - ln_min) * i / 120.0)
				var xv: float = log(kk2)
				var yv: float = fit["a"] * xv * xv + fit["b"] * xv + fit["c"]
				var pt := Vector2(fx.call(kk2), clamp(fy.call(yv), pad_t, size.y - pad_b))
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
