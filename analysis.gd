class_name Analysis
# Statistiques du sens finder.
#
# Méthode (sources : Aim Lab sens finder ; Boudaoud et al., IEEE CoG 2022,
# "Mouse Sensitivity in First-person Targeting Tasks" ; ISO 9241-9) :
#  - performance par round mesurée en débit de Fitts (throughput, bits/s) :
#    chaque kill vaut ID = log2(1 + D/W) bits (D = distance angulaire au spawn,
#    W = diamètre angulaire de la cible). TP effectif = Σ ID / durée de phase.
#    Ce débit normalise la difficulté (distance/taille) entre les cibles.
#  - ajustement d'une parabole pondérée score = a·x² + b·x + c, x = ln(k),
#    pondérée par le nombre de kills du round (proxy de variance).
#  - l'optimum est une PLAGE, pas un point : stabilité estimée par
#    leave-one-out (dispersion des sommets quand on retire un round).

const K_MIN := 0.62
const K_MAX := 1.45

static func median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	var m := s.size() / 2
	if s.size() % 2 == 1:
		return s[m]
	return (s[m - 1] + s[m]) / 2.0

static func _det3(M: Array) -> float:
	return (M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1])
		- M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0])
		+ M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0]))

static func _rep(M: Array, col: int, V: Array) -> Array:
	var out := []
	for i in 3:
		var row := []
		for j in 3:
			row.append(V[i] if j == col else M[i][j])
		out.append(row)
	return out

# Parabole pondérée par moindres carrés. Retourne {a, b, c, r2}.
static func wfit(xs: Array, ys: Array, ws: Array) -> Dictionary:
	var sw := 0.0; var sx := 0.0; var sx2 := 0.0; var sx3 := 0.0; var sx4 := 0.0
	var sy := 0.0; var sxy := 0.0; var sx2y := 0.0
	for i in xs.size():
		var w: float = ws[i]
		var x: float = xs[i]
		var y: float = ys[i]
		sw += w
		sx += w * x; sx2 += w * x * x; sx3 += w * x * x * x; sx4 += w * x * x * x * x
		sy += w * y; sxy += w * x * y; sx2y += w * x * x * y
	var M := [[sx4, sx3, sx2], [sx3, sx2, sx], [sx2, sx, sw]]
	var V := [sx2y, sxy, sy]
	var det := _det3(M)
	var a := 0.0; var b := 0.0; var c := sy / maxf(sw, 1e-9)
	if abs(det) > 1e-9:
		a = _det3(_rep(M, 0, V)) / det
		b = _det3(_rep(M, 1, V)) / det
		c = _det3(_rep(M, 2, V)) / det
	# R² pondéré
	var ybar := sy / maxf(sw, 1e-9)
	var ss_tot := 0.0
	var ss_res := 0.0
	for i in xs.size():
		var pred: float = a * xs[i] * xs[i] + b * xs[i] + c
		ss_tot += ws[i] * pow(ys[i] - ybar, 2)
		ss_res += ws[i] * pow(ys[i] - pred, 2)
	var r2 := 0.0
	if ss_tot > 1e-9:
		r2 = clamp(1.0 - ss_res / ss_tot, 0.0, 1.0)
	return {"a": a, "b": b, "c": c, "r2": r2}

# k optimal depuis un fit ; fallback = k du meilleur score mesuré
static func kopt_from(f: Dictionary, ks: Array, ys: Array) -> float:
	if f["a"] < -1e-4:
		return clamp(exp(-f["b"] / (2.0 * f["a"])), K_MIN, K_MAX)
	var bi := 0
	for i in ys.size():
		if ys[i] > ys[bi]:
			bi = i
	return clamp(ks[bi], K_MIN, K_MAX)

# Dispersion leave-one-out des optima (fraction du k central)
static func loo_spread(ks: Array, ys: Array, ws: Array) -> float:
	if ks.size() < 4:
		return 1.0
	var opts: Array = []
	for skip in ks.size():
		var xs2: Array = []; var ys2: Array = []; var ws2: Array = []
		for i in ks.size():
			if i == skip:
				continue
			xs2.append(log(ks[i])); ys2.append(ys[i]); ws2.append(ws[i])
		var f := wfit(xs2, ys2, ws2)
		if f["a"] < -1e-4:
			opts.append(clamp(exp(-f["b"] / (2.0 * f["a"])), K_MIN, K_MAX))
	if opts.size() < 3:
		return 1.0
	var lo: float = opts.min()
	var hi: float = opts.max()
	var mid := (lo + hi) * 0.5
	return (hi - lo) / maxf(mid, 0.01)
