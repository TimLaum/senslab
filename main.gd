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

const MODES := {
	"grid": {"name": "GRIDSHOT", "desc": "3 cibles simultanées · vitesse brute", "type": "click",
		"simul": 3, "r": 0.45, "cone": 26.0, "p_lo": -2.0, "p_hi": 16.0, "anchored": true},
	"micro": {"name": "MICROSHOT", "desc": "micro-corrections · petites cibles proches", "type": "click",
		"simul": 1, "r": 0.16, "cone": 10.0, "p_lo": -4.0, "p_hi": 8.0, "anchored": false},
	"flick": {"name": "FLICKSHOT", "desc": "flicks longs · distance variable", "type": "click",
		"simul": 1, "r": 0.30, "cone": 35.0, "p_lo": -4.0, "p_hi": 18.0, "anchored": false},
	"head": {"name": "HEAD LINE", "desc": "headshots · cibles têtes sur une ligne", "type": "click",
		"simul": 1, "r": 0.18, "cone": 30.0, "p_lo": 1.0, "p_hi": 2.2, "anchored": false},
	"strafe": {"name": "STRAFE TRACK", "desc": "tracking lisse · strafes amples", "type": "track_smooth"},
	"react": {"name": "REACTIVE TRACK", "desc": "tracking réactif · inversions brutales", "type": "track_react"},
}
const MODE_ORDER := ["grid", "micro", "flick", "head", "strafe", "react"]
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
var trk_kind := "smooth"
var trk_anchor_yaw := 0.0
var trk_yaw := 0.0
var trk_v := 24.0
var trk_pitch_base := 6.0
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

# classement en ligne
var lb: Leaderboard
var pseudo := ""
var lb_mode := "grid"
var lb_dur := 60

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
var lb_mode_btns := {}
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
var tres_stats: Label

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
	_build_world()
	_build_sounds()
	_build_ui()
	_load_prefs()
	_goto_menu()

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
	for entry in [["train", "ENTRAÎNEMENT"], ["finder", "SENS FINDER"], ["board", "CLASSEMENT"], ["settings", "RÉGLAGES"]]:
		var nb := _nav_btn(entry[1])
		nb.pressed.connect(_show_tab.bind(entry[0]))
		nav_btns[entry[0]] = nb
		side.add_child(nb)
	var spv := Control.new()
	spv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spv)
	last_calib_lbl = UIKit.label("", 11, UIKit.COL_MUTED, true)
	last_calib_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(last_calib_lbl)
	side.add_child(HSeparator.new())
	var quit := _nav_btn("QUITTER")
	quit.pressed.connect(func(): get_tree().quit())
	side.add_child(quit)

	var content := Control.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)

	tab_panels["train"] = _build_tab_train()
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
	v.add_child(UIKit.label("6 exercices · records enregistrés par durée · la sens et le fov du jeu sélectionné s'appliquent", 12, UIKit.COL_MUTED))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for mk in MODE_ORDER:
		var m: Dictionary = MODES[mk]
		var c := _card(mk, m["name"], m["desc"], "", 118.0)
		c["btn"].pressed.connect(_start_train.bind(mk))
		mode_rec_lbls[mk] = c["extra"]
		grid.add_child(c["btn"])
	v.add_child(grid)
	return v

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
	mrow.add_theme_constant_override("separation", 8)
	for mk in MODE_ORDER:
		var mb := UIKit.btn(MODES[mk]["name"], false, 12)
		mb.pressed.connect(_lb_set_mode.bind(mk))
		lb_mode_btns[mk] = mb
		mrow.add_child(mb)
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

func _lb_set_mode(mk: String) -> void:
	lb_mode = mk
	_lb_refresh()

func _lb_set_dur(d: int) -> void:
	lb_dur = d
	_lb_refresh()

func _lb_refresh() -> void:
	for mk in lb_mode_btns:
		UIKit.set_btn_selected(lb_mode_btns[mk], mk == lb_mode)
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
		return
	if rows.is_empty():
		lb_status.text = "aucun score en %s · %d s — sois le premier !" % [MODES[lb_mode]["name"], lb_dur]
		return
	lb_status.text = "%s · %d s · top %d" % [MODES[lb_mode]["name"], lb_dur, rows.size()]
	for h in ["#", "PSEUDO", "SCORE"]:
		lb_grid.add_child(UIKit.label(h, 11, UIKit.COL_MUTED, true))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var me: bool = str(r.get("player", "")) == pseudo and pseudo != ""
		var col := UIKit.COL_ACCENT2 if me else (UIKit.COL_TEXT if i < 3 else UIKit.COL_MUTED)
		lb_grid.add_child(UIKit.label("%d" % (i + 1), 13, col, true))
		lb_grid.add_child(UIKit.label(str(r.get("player", "?")), 13, col, true))
		lb_grid.add_child(UIKit.label(str(int(r.get("score", 0))), 13, col, true))

func _on_lb_submitted(ok: bool) -> void:
	if tres_net != null and mode == Mode.T_RESULTS:
		tres_net.text = "✓ score envoyé au classement" if ok else "⚠ envoi au classement échoué"

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
		_prefs_set("pseudo", pseudo))
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
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.COL_PANEL, UIKit.COL_LINE))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(520, 0)
	card.add_child(v)
	tres_title = UIKit.label("", 12, UIKit.COL_ACCENT, true)
	tres_score = UIKit.label("", 52, UIKit.COL_TEXT, true)
	tres_record = UIKit.label("", 13, UIKit.COL_ACCENT2, true)
	tres_stats = UIKit.label("", 13, UIKit.COL_MUTED, true)
	tres_net = UIKit.label("", 12, UIKit.COL_MUTED, true)
	for n in [tres_title, tres_score, tres_record, tres_stats, tres_net]:
		v.add_child(n)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var b1 := UIKit.btn("REJOUER", true, 13)
	b1.pressed.connect(func(): _start_train(t_mode))
	var b2 := UIKit.btn("MENU", false, 13)
	b2.pressed.connect(_goto_menu)
	for b in [b1, b2]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	v.add_child(actions)
	tres_panel = UIKit.overlay_wrap(card)
	ui.add_child(tres_panel)

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
	sum_lbl.text = "%s · sens %s · %d dpi · edpi %d" % [
		GameDB.get_game(game)["label"], GameDB.fmt_sens(game, sens), int(dpi), int(sens * dpi)]

func _set_duration(d: int) -> void:
	t_dur = d
	for i in DURATIONS.size():
		UIKit.set_btn_selected(dur_btns[i], DURATIONS[i] == d)
	_refresh_mode_records()

func _refresh_mode_records() -> void:
	for mk in MODE_ORDER:
		var rec := _get_record(mk, t_dur)
		mode_rec_lbls[mk].text = ("record %d · %ds" % [rec, t_dur]) if rec > 0 else ("pas encore de record en %ds" % t_dur)

func _refresh_last_calib() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://senslab.cfg") == OK:
		var last: Dictionary = cf.get_value("results", "last", {})
		if not last.is_empty():
			last_calib_lbl.text = "dernière calibration : %s %s (plage %s – %s)" % [
				last.get("label", ""), last.get("sens", ""), last.get("lo", ""), last.get("hi", "")]
			return
	last_calib_lbl.text = "aucune calibration enregistrée"

func _goto_menu() -> void:
	mode = Mode.MENU
	paused = false
	trk_active = false
	_clear_targets()
	hud_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_mode_records()
	_refresh_last_calib()
	_refresh_derived()
	_show_only(menu_panel)

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
	_spawn_tracker("smooth")

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

func _pop_fx(pos: Vector3, r_m: float) -> void:
	var mi := _make_sphere(r_m, UIKit.COL_ACCENT)
	var m: StandardMaterial3D = mi.material_override
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.28, 0.33, 0.8)
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
		if int(m["simul"]) == 1:
			cur["errs"].append(_ballistic_err())
		t_combo += 1
		t_best_streak = max(t_best_streak, t_combo)
		t_score += 100 + 4 * min(t_combo, 25)
		_remove_target(hit_t)
		if int(m["simul"]) == 1:
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
func _spawn_tracker(kind: String) -> void:
	_clear_targets()
	trk_kind = kind
	trk_anchor_yaw = yaw
	trk_yaw = yaw + 8.0
	trk_v = 24.0 if kind == "smooth" else 46.0
	trk_pitch_base = clamp(pitch * 0.3 + 6.0, 0.0, 14.0)
	trk_ph = randf_range(0.0, 6.0)
	trk_flip_in = randf_range(0.3, 0.8)
	var node := _make_sphere(0.33, UIKit.COL_ACCENT)
	add_child(node)
	targets = [{"node": node, "ang": Vector2.ZERO, "r_ang": rad_to_deg(asin(0.33 / R_DIST)),
		"born": Time.get_ticks_msec(), "d0": 0.0}]
	trk_active = true

func _update_track(delta: float) -> void:
	if not trk_active or targets.is_empty():
		return
	var t: Dictionary = targets[0]
	if trk_kind == "smooth":
		trk_v += randf_range(-1.0, 1.0) * 80.0 * delta
		trk_v = clamp(trk_v, -42.0, 42.0)
		if abs(trk_v) < 14.0:
			trk_v = 14.0 * (1.0 if trk_v >= 0.0 else -1.0)
	else:
		# réactif : vitesse constante, inversions brutales aléatoires
		trk_flip_in -= delta
		if trk_flip_in <= 0.0:
			trk_v = -trk_v * randf_range(0.9, 1.1)
			trk_flip_in = randf_range(0.25, 0.7)
	trk_yaw += trk_v * delta
	var band := 26.0 if trk_kind == "smooth" else 20.0
	if trk_yaw > trk_anchor_yaw + band:
		trk_yaw = trk_anchor_yaw + band
		trk_v = -abs(trk_v)
	elif trk_yaw < trk_anchor_yaw - band:
		trk_yaw = trk_anchor_yaw - band
		trk_v = abs(trk_v)
	trk_ph += delta * 1.7
	var t_pitch: float = trk_pitch_base + sin(trk_ph) * (3.5 if trk_kind == "smooth" else 1.5)
	t["node"].position = cam.position + _dir_from_angles(trk_yaw, t_pitch) * R_DIST
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

func _start_train_run() -> void:
	mode = Mode.TRAIN
	paused = false
	phase_timer = float(t_dur)
	var m: Dictionary = MODES[t_mode]
	if m["type"] == "click":
		anchor_yaw = yaw
		hud_hint.text = "clique les cibles"
		for i in int(m["simul"]):
			_spawn_train_target()
	elif m["type"] == "track_smooth":
		hud_hint.text = "garde le viseur sur la cible"
		_spawn_tracker("smooth")
	else:
		hud_hint.text = "suis les inversions"
		_spawn_tracker("react")
	_refresh_play_hud()

func _spawn_train_target() -> void:
	var m: Dictionary = MODES[t_mode]
	var base := anchor_yaw if m["anchored"] else yaw
	var t := _spawn_click(m["r"], m["cone"], m["p_lo"], m["p_hi"], base, 1.5)
	if int(m["simul"]) == 1:
		_begin_path(t["ang"])

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
	var stats := ""
	if m["type"] == "click":
		var tot: int = cur["hits"] + cur["misses"]
		var acc := float(cur["hits"]) / tot * 100.0 if tot > 0 else 0.0
		stats = "cibles %d · précision %d%% · flick médian %.2fs · meilleure série %d" % [
			cur["hits"], int(acc), Analysis.median(cur["tth"]), t_best_streak]
		if cur["errs"].size() > 3:
			var werr := 0.0
			for e in cur["errs"]:
				werr += e
			werr /= cur["errs"].size()
			if werr > 0.05:
				stats += "\ntendance overshoot (+%d%%) — tu dépasses la cible" % int(werr * 100)
			elif werr < -0.05:
				stats += "\ntendance undershoot (%d%%) — tu t'arrêtes avant la cible" % int(werr * 100)
	else:
		var pct := 0.0
		if cur["trk_tot"] > 0.0:
			pct = cur["trk_on"] / cur["trk_tot"] * 100.0
		stats = "temps sur cible %d%%" % int(pct)
	tres_stats.text = stats
	mode = Mode.T_RESULTS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud_root.visible = false
	_show_only(tres_panel)
	# envoi au classement en ligne
	if not lb.configured():
		tres_net.text = ""
	elif pseudo == "":
		tres_net.text = "pas de pseudo → score non envoyé au classement (RÉGLAGES)"
	else:
		tres_net.text = "envoi au classement…"
		lb.submit(pseudo, t_mode, t_dur, t_score)

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
		Mode.TRAIN:
			if not paused:
				phase_timer -= delta
				hud_timer.text = "⏱ %4.1fs" % max(phase_timer, 0.0)
				var m: Dictionary = MODES[t_mode]
				if m["type"] != "click":
					_update_track(delta)
					_refresh_play_hud()
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
