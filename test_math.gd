extends SceneTree
# Validation du pipeline : détrend → GP → argmax → bootstrap.
# Joueur synthétique : optimum vrai k0, courbe en U sur ln(k), bruit gaussien,
# effet d'apprentissage +8 pts sur la session. Le pipeline doit retrouver k0.

func _gauss() -> float:
	return sqrt(-2.0 * log(maxf(randf(), 1e-9))) * cos(TAU * randf())

func _initialize() -> void:
	randomize()
	var k0 := 0.95
	var protocol_ks := [1.0, 0.72, 0.85, 1.18, 1.32, 0.90, 1.05]
	var hits_ok := 0
	var range_ok := 0
	var errs: Array = []
	var trials := 40
	for trial in trials:
		var xs: Array = []
		var ys: Array = []
		var ws: Array = []
		var ts: Array = []
		for i in protocol_ks.size():
			var x: float = log(protocol_ks[i])
			var t := float(i) / (protocol_ks.size() - 1.0)
			var y := 82.0 - 55.0 * pow(x - log(k0), 2.0) + 8.0 * t + _gauss() * 4.0
			xs.append(x)
			ys.append(y)
			ws.append(20.0)
			ts.append(t)
		var dt := Analysis.detrend(xs, ys, ws, ts)
		var f := Analysis.wfit(xs, dt["ys"], ws)
		var sn2 := Analysis.noise_from_fit(xs, dt["ys"], ws, f)
		var g := Analysis.gp_fit(xs, dt["ys"], ws, sn2, true)
		if not g["ok"]:
			continue
		var sc := Analysis.gp_scan(g, 2.5, float(xs.min()) - 0.02, float(xs.max()) + 0.02)
		var bs := Analysis.bootstrap_range(xs, dt["ys"], ws, sn2, 140)
		var khat: float = sc["k"]
		if bs["ok"]:
			khat = exp(0.5 * (log(float(sc["k"])) + log(float(bs["med"]))))
		var e: float = absf(log(khat / k0))
		errs.append(e)
		if e < 0.09:
			hits_ok += 1
		var lo: float = maxf(sc["lo"], bs["lo"] if bs["ok"] else 0.0)
		var hi: float = minf(sc["hi"], bs["hi"] if bs["ok"] else 9.0)
		if lo <= k0 and k0 <= hi:
			range_ok += 1
		if trial == 0:
			print("ex.: khat=%.3f  plateau=[%.3f, %.3f]  bootstrap=[%.3f, %.3f]  ucb_next=%.3f  trend=%.1f" % [
				khat, sc["lo"], sc["hi"], bs["lo"], bs["hi"],
				Analysis.gp_next_ucb(g, protocol_ks), dt["trend"]])
	# Borne théorique (delta method, 7 rounds, sigma=4, courbure 55) :
	# SD(ln khat) >= ~0.073 → au mieux ~75 % des essais sous 9 % d'erreur.
	print("argmax: %d/%d à moins de 9%% de k0 · erreur médiane ln = %.3f (borne ~0.049)" % [
		hits_ok, trials, Analysis.median(errs)])
	print("plage (plateau ∩ bootstrap) contient k0 : %d/%d" % [range_ok, trials])
	# TP effectif : resserrer les impacts doit augmenter le TP
	var tp_loose := Analysis.tp_effective([20.0, 22.0, 18.0, 21.0],
		[2.0, -1.5, 1.0, 2.5, -2.0, 0.5], [0.5, 0.6, 0.55, 0.5])
	var tp_tight := Analysis.tp_effective([20.0, 22.0, 18.0, 21.0],
		[0.5, -0.3, 0.2, 0.6, -0.4, 0.1], [0.5, 0.6, 0.55, 0.5])
	print("TP loose=%.2f < TP tight=%.2f : %s" % [tp_loose, tp_tight, str(tp_loose < tp_tight)])
	var ok := (hits_ok >= int(trials * 0.5) and Analysis.median(errs) <= 0.08
		and range_ok >= int(trials * 0.7) and tp_loose < tp_tight)
	print("MATH OK" if ok else "MATH FAIL")
	quit()
