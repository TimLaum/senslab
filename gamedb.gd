class_name GameDB
# Base des jeux supportés : yaw (deg/count à sens 1), FOV et conventions.
# fov_mode : "h169" = FOV horizontal 16:9 (valeur du slider en jeu)
#            "h43"  = FOV horizontal base 4:3 (Apex / Source)

const GAMES := {
	"valorant": {
		"label": "VALORANT", "yaw": 0.07, "def": 0.4, "dec": 3,
		"fov_def": 103.0, "fov_lock": true, "fov_mode": "h169", "fov_hint": "103 (fixe)",
	},
	"cs2": {
		"label": "CS2", "yaw": 0.022, "def": 1.27, "dec": 2,
		"fov_def": 106.26, "fov_lock": true, "fov_mode": "h169", "fov_hint": "106.26 (fixe, = 90 en 4:3)",
	},
	"ow2": {
		"label": "OVERWATCH 2", "yaw": 0.0066, "def": 5.0, "dec": 2,
		"fov_def": 103.0, "fov_lock": false, "fov_mode": "h169", "fov_hint": "80–103, défaut 103",
	},
	"apex": {
		"label": "APEX LEGENDS", "yaw": 0.022, "def": 2.0, "dec": 2,
		"fov_def": 90.0, "fov_lock": false, "fov_mode": "h43", "fov_hint": "70–110 (échelle du jeu), défaut 90",
	},
	"cod": {
		"label": "COD / WARZONE", "yaw": 0.0066, "def": 6.0, "dec": 2,
		"fov_def": 80.0, "fov_lock": false, "fov_mode": "h169", "fov_hint": "60–120, défaut 80",
	},
}

static func keys() -> Array:
	return ["valorant", "cs2", "ow2", "apex", "cod"]

static func get_game(key: String) -> Dictionary:
	return GAMES[key]

# FOV horizontal équivalent 16:9, quel que soit le mode d'affichage du jeu
static func hfov169(key: String, fov_val: float) -> float:
	var g: Dictionary = GAMES[key]
	var v: float = clamp(fov_val, 50.0, 140.0)
	if g["fov_mode"] == "h43":
		return rad_to_deg(2.0 * atan(tan(deg_to_rad(v * 0.5)) * 4.0 / 3.0))
	return v

# FOV vertical pour la caméra Godot à l'aspect réel de l'écran
static func vfov(key: String, fov_val: float, aspect: float) -> float:
	var h := hfov169(key, fov_val)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(h * 0.5)) / aspect))

static func cm360(key: String, sens: float, dpi: float) -> float:
	var yaw: float = GAMES[key]["yaw"]
	return 360.0 / (yaw * sens * dpi) * 2.54

static func convert_sens(sens: float, from_key: String, to_key: String) -> float:
	return sens * GAMES[from_key]["yaw"] / GAMES[to_key]["yaw"]

static func fmt_sens(key: String, s: float) -> String:
	return "%.*f" % [int(GAMES[key]["dec"]), s]
