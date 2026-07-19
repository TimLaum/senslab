class_name Analysis
# Statistiques du sens finder.
#
# Sources : MacKenzie, "Fitts' Law" (ch. 17, Handbook of HCI 2018) — throughput
# effectif ISO 9241-9 (We = 4,133·SD des impacts, IDe = log2(Ae/We+1)) ;
# Boudaoud/Spjut et al. (NVIDIA), arXiv:2203.12050 + IEEE CoG 2023 — l'optimum
# de sens FPS est un large plateau en U sur échelle log, l'adaptation à une
# nouvelle sens contamine le début de chaque essai ; Casiez & Vogel 2008 (CD
# gain) ; Frazier, arXiv:1807.02811 — optimisation bayésienne (GP + UCB).
#
# Pipeline :
#  1. score par round = débit de Fitts EFFECTIF (bits/s) + tracking,
#     échauffement de début de round exclu ;
#  2. détrend : un terme linéaire d'apprentissage (ordre des rounds) est
#     co-ajusté puis retiré, sinon les derniers k testés sont favorisés ;
#  3. régression par PROCESSUS GAUSSIEN (noyau RBF sur ln k, bruit pondéré
#     par le nombre de cibles) → moyenne a posteriori + incertitude ;
#  4. rounds adaptatifs placés par UCB (mu + kappa·sigma) ;
#  5. plage recommandée = plateau du GP (mu >= mu* − 2,5 pts) ∩ intervalle
#     bootstrap (10e–90e percentile de l'argmax sur 140 rééchantillonnages).

const K_MIN := 0.62
const K_MAX := 1.45
const GP_LEN := 0.22          # longueur du noyau RBF, en ln(k)
const GRID_N := 161

static func median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	var m := s.size() / 2
	if s.size() % 2 == 1:
		return s[m]
	return (s[m - 1] + s[m]) / 2.0

static func mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()

static func sd(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := mean(a)
	var s := 0.0
	for v in a:
		s += (v - m) * (v - m)
	return sqrt(s / (a.size() - 1))

# ------------------------------------------------------------
#  Throughput effectif (ISO 9241-9 / MacKenzie)
#  d0s : distance angulaire initiale des cibles touchées (Ae)
#  ends : erreur angulaire du viseur à CHAQUE clic, ratés inclus (→ We)
#  mts : temps par cible touchée (s)
#  Retourne -1 si trop peu de données (fallback ID nominal côté appelant).
# ------------------------------------------------------------
static func tp_effective(d0s: Array, ends: Array, mts: Array) -> float:
	if d0s.size() < 4 or ends.size() < 5 or mts.size() < 4:
		return -1.0
	var ae := mean(d0s)
	var we := 4.133 * sd(ends)
	we = maxf(we, 0.25)
	var mt := mean(mts)
	if mt <= 0.05 or ae <= 0.1:
		return -1.0
	return log(ae / we + 1.0) / log(2.0) / mt

# ------------------------------------------------------------
#  Résolution d'un système linéaire n×n (pivot partiel)
# ------------------------------------------------------------
static func gauss(A_in: Array, b_in: Array) -> Array:
	var n := b_in.size()
	var A := []
	for i in n:
		A.append((A_in[i] as Array).duplicate())
	var b := b_in.duplicate()
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf(A[r][col]) > absf(A[piv][col]):
				piv = r
		if absf(A[piv][col]) < 1e-11:
			return []
		if piv != col:
			var tr = A[piv]; A[piv] = A[col]; A[col] = tr
			var tb = b[piv]; b[piv] = b[col]; b[col] = tb
		for r in range(col + 1, n):
			var f: float = A[r][col] / A[col][col]
			if f == 0.0:
				continue
			for c2 in range(col, n):
				A[r][c2] -= f * A[col][c2]
			b[r] -= f * b[col]
	var x := []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = b[i]
		for j in range(i + 1, n):
			s -= A[i][j] * x[j]
		x[i] = s / A[i][i]
	return x

# ------------------------------------------------------------
#  Détrend de l'apprentissage : moindres carrés pondérés
#  y = b0 + b1·x + b2·x² + b3·t  (t = ordre du round, 0..1)
#  → renvoie les scores corrigés y − b3·(t − t̄)
# ------------------------------------------------------------
static func detrend(xs: Array, ys: Array, ws: Array, ts: Array) -> Dictionary:
	var n := xs.size()
	if n < 6:
		return {"ys": ys.duplicate(), "trend": 0.0}
	var M := []
	var V := []
	for i in 4:
		M.append([0.0, 0.0, 0.0, 0.0])
		V.append(0.0)
	var sw := 0.0
	var st := 0.0
	for i in n:
		var w: float = ws[i]
		var phi := [1.0, xs[i], xs[i] * xs[i], ts[i]]
		for a in 4:
			V[a] += w * phi[a] * ys[i]
			for b in 4:
				M[a][b] += w * phi[a] * phi[b]
		sw += w
		st += w * ts[i]
	# ridge sur le trend : peu de points → colinéarité x/t, on rétrécit b3
	M[3][3] += 0.5 * sw
	var sol := gauss(M, V)
	if sol.is_empty():
		return {"ys": ys.duplicate(), "trend": 0.0}
	var b3: float = clampf(sol[3], -30.0, 30.0)
	var tbar := st / maxf(sw, 1e-9)
	var out := []
	for i in n:
		out.append(ys[i] - b3 * (ts[i] - tbar))
	return {"ys": out, "trend": b3}

# ------------------------------------------------------------
#  Parabole pondérée (conservée : R² affiché, bruit, fallback)
# ------------------------------------------------------------
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

# variance résiduelle pondérée autour de la parabole → bruit du GP
static func noise_from_fit(xs: Array, ys: Array, ws: Array, f: Dictionary) -> float:
	var sw := 0.0
	var sr := 0.0
	for i in xs.size():
		var pred: float = f["a"] * xs[i] * xs[i] + f["b"] * xs[i] + f["c"]
		sr += ws[i] * pow(ys[i] - pred, 2)
		sw += ws[i]
	if sw <= 0.0:
		return 25.0
	return clampf(sr / sw, 6.0, 400.0)

static func kopt_from(f: Dictionary, ks: Array, ys: Array) -> float:
	if f["a"] < -1e-4:
		return clamp(exp(-f["b"] / (2.0 * f["a"])), K_MIN, K_MAX)
	var bi := 0
	for i in ys.size():
		if ys[i] > ys[bi]:
			bi = i
	return clamp(ks[bi], K_MIN, K_MAX)

# ------------------------------------------------------------
#  Processus gaussien — noyau RBF sur ln(k), bruit ∝ 1/poids
# ------------------------------------------------------------
# GP semi-paramétrique : la moyenne a priori est la parabole pondérée (le GP ne
# modélise que les résidus). Loin des données, la prédiction retombe sur la
# parabole (forme en U attendue) au lieu d'une constante — pas de faux optimum
# de bord par extrapolation.
static func gp_fit(xs: Array, ys: Array, ws: Array, sn2: float, with_var: bool = true) -> Dictionary:
	var n := xs.size()
	if n < 4:
		return {"ok": false}
	var pf := wfit(xs, ys, ws)
	var ma: float = pf["a"]
	var mb: float = pf["b"]
	var mc: float = pf["c"]
	if ma > -1e-4:
		# parabole plate ou inversée : moyenne constante pondérée
		ma = 0.0
		mb = 0.0
		var sw0 := 0.0
		var sy0 := 0.0
		for i in n:
			sw0 += ws[i]
			sy0 += ws[i] * ys[i]
		mc = sy0 / maxf(sw0, 1e-9)
	# résidus autour de la moyenne a priori
	var yc := []
	var sw := 0.0
	var rvar := 0.0
	for i in n:
		var res: float = ys[i] - (ma * xs[i] * xs[i] + mb * xs[i] + mc)
		yc.append(res)
		rvar += ws[i] * res * res
		sw += ws[i]
	rvar /= maxf(sw, 1e-9)
	var sf2 := clampf(rvar * 2.0, 20.0, 900.0)
	var wbar := sw / n
	var K := []
	for i in n:
		var row := []
		for j in n:
			var v: float = sf2 * exp(-0.5 * pow((xs[i] - xs[j]) / GP_LEN, 2.0))
			if i == j:
				v += maxf(sn2, 6.0) * wbar / maxf(ws[i], 0.5)
			row.append(v)
		K.append(row)
	var alpha := gauss(K, yc)
	if alpha.is_empty():
		return {"ok": false}
	var g := {"ok": true, "xs": xs.duplicate(), "alpha": alpha, "sf2": sf2,
		"sn2": sn2, "ma": ma, "mb": mb, "mc": mc, "Kinv": []}
	if with_var:
		var kinv := []
		for i in n:
			var e := []
			for j in n:
				e.append(1.0 if j == i else 0.0)
			var coli := gauss(K, e)
			if coli.is_empty():
				return {"ok": false}
			kinv.append(coli)
		g["Kinv"] = kinv
	return g

static func _gp_mean(g: Dictionary, x: float) -> float:
	return g["ma"] * x * x + g["mb"] * x + g["mc"]

static func gp_mu(g: Dictionary, x: float) -> float:
	var xs: Array = g["xs"]
	var mu := _gp_mean(g, x)
	for i in xs.size():
		mu += g["sf2"] * exp(-0.5 * pow((x - xs[i]) / GP_LEN, 2.0)) * g["alpha"][i]
	return mu

static func gp_mu_var(g: Dictionary, x: float) -> Vector2:
	var xs: Array = g["xs"]
	var n := xs.size()
	var kv := []
	var mu := _gp_mean(g, x)
	for i in n:
		var kk: float = g["sf2"] * exp(-0.5 * pow((x - xs[i]) / GP_LEN, 2.0))
		kv.append(kk)
		mu += kk * g["alpha"][i]
	var v: float = g["sf2"]
	var kinv: Array = g["Kinv"]
	if not kinv.is_empty():
		for i in n:
			var s := 0.0
			for j in n:
				s += kinv[i][j] * kv[j]
			v -= kv[i] * s
	return Vector2(mu, maxf(v, 0.0))

# balayage : argmax et plateau restreints à [xlo, xhi] (la plage testée —
# on ne recommande pas une sens jamais mesurée), courbe complète pour l'affichage
static func gp_scan(g: Dictionary, drop: float = 2.5, xlo: float = -10.0, xhi: float = 10.0) -> Dictionary:
	var lnmin := log(K_MIN)
	var lnmax := log(K_MAX)
	var ks := PackedFloat32Array()
	var mus := PackedFloat32Array()
	var sds := PackedFloat32Array()
	var bi := -1
	var bmu := -1e18
	var ilo := GRID_N - 1
	var ihi := 0
	for i in GRID_N:
		var x := lnmin + (lnmax - lnmin) * i / (GRID_N - 1.0)
		var mv := gp_mu_var(g, x)
		ks.append(exp(x))
		mus.append(mv.x)
		sds.append(sqrt(mv.y))
		if x >= xlo and x <= xhi:
			ilo = mini(ilo, i)
			ihi = maxi(ihi, i)
			if mv.x > bmu:
				bmu = mv.x
				bi = i
	if bi < 0:
		bi = GRID_N / 2
		bmu = mus[bi]
		ilo = 0
		ihi = GRID_N - 1
	var lo := bi
	while lo > ilo and mus[lo - 1] >= bmu - drop:
		lo -= 1
	var hi := bi
	while hi < ihi and mus[hi + 1] >= bmu - drop:
		hi += 1
	return {"k": ks[bi], "mu": bmu, "sigma": sds[bi], "lo": ks[lo], "hi": ks[hi],
		"ks": ks, "mus": mus, "sds": sds}

# prochain k à tester : UCB (mu + kappa·sigma), loin des k déjà testés
static func gp_next_ucb(g: Dictionary, tested: Array, kappa: float = 1.3) -> float:
	var lnmin := log(K_MIN)
	var lnmax := log(K_MAX)
	var best := -1e18
	var bk := 1.0
	for i in GRID_N:
		var x := lnmin + (lnmax - lnmin) * i / (GRID_N - 1.0)
		var near := false
		for t in tested:
			if absf(x - log(t)) < 0.06:
				near = true
				break
		if near:
			continue
		var mv := gp_mu_var(g, x)
		var u: float = mv.x + kappa * sqrt(mv.y)
		if u > best:
			best = u
			bk = exp(x)
	if best <= -1e17:
		return gp_scan(g)["k"]
	return clampf(bk, K_MIN, K_MAX)

# ------------------------------------------------------------
#  Bootstrap de l'argmax : rounds rééchantillonnés avec remise,
#  refit GP (moyenne seule), percentiles 10–90 des optima.
# ------------------------------------------------------------
static func bootstrap_range(xs: Array, ys: Array, ws: Array, sn2: float, B: int = 140) -> Dictionary:
	var n := xs.size()
	var opts: Array = []
	var lnmin: float = xs.min() - 0.02
	var lnmax: float = xs.max() + 0.02
	for b in B:
		var xi := []
		var yi := []
		var wi := []
		var distinct := {}
		for i in n:
			var j := randi() % n
			xi.append(xs[j])
			yi.append(ys[j])
			wi.append(ws[j])
			distinct[xs[j]] = true
		if distinct.size() < 4:
			continue
		var g := gp_fit(xi, yi, wi, sn2, false)
		if not g["ok"]:
			continue
		var best := -1e18
		var bk := 1.0
		for t in 61:
			var x := lnmin + (lnmax - lnmin) * t / 60.0
			var mu := gp_mu(g, x)
			if mu > best:
				best = mu
				bk = exp(x)
		opts.append(bk)
	if opts.size() < 30:
		return {"ok": false, "lo": K_MIN, "hi": K_MAX, "med": 1.0}
	opts.sort()
	# médiane = estimateur baggé de l'optimum (variance réduite vs fit unique)
	return {"ok": true,
		"lo": opts[int(opts.size() * 0.05)],
		"hi": opts[int(opts.size() * 0.95)],
		"med": opts[opts.size() / 2]}

# Dispersion leave-one-out (fallback si le GP échoue)
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
