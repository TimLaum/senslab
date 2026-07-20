class_name Leaderboard
extends Node
# Classement en ligne partagé (Supabase REST).
# Les scores partent en HTTPS vers la table `scores` ; le top est lu
# depuis la vue `leaderboard` (meilleur score par joueur/mode/durée).

const URL := "https://wgormjfogsvvcumboqnv.supabase.co"
const KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indnb3JtamZvZ3N2dmN1bWJvcW52Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQzODgyMDksImV4cCI6MjA5OTk2NDIwOX0.g-RnEs_tqDC327SzN-08NB10mZF2clKXWCLrpI9pLBg"

signal top_received(ok: bool, rows: Array)
signal submitted(ok: bool)
signal replay_received(ok: bool, player: String, data: String)
signal all_received(ok: bool, rows: Array)

func configured() -> bool:
	return URL.begins_with("https://")

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + KEY,
		"Authorization: Bearer " + KEY,
		"Content-Type: application/json",
	])

func submit(player: String, mode: String, duration: int, score: int, stats: Dictionary = {}) -> void:
	if not configured():
		submitted.emit(false)
		return
	var hr := HTTPRequest.new()
	hr.timeout = 8.0
	add_child(hr)
	var done := func(_result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		hr.queue_free()
		submitted.emit(code >= 200 and code < 300)
	hr.request_completed.connect(done)
	var h := _headers()
	h.append("Prefer: return=minimal")
	var body := JSON.stringify({
		"player": player.substr(0, 20), "mode": mode,
		"duration": duration, "score": score,
		"acc": float(stats.get("acc", 0.0)),
		"streak": int(stats.get("streak", 0)),
		"hits": int(stats.get("hits", 0)),
		"shots": int(stats.get("shots", 0))})
	if hr.request(URL + "/rest/v1/scores", h, HTTPClient.METHOD_POST, body) != OK:
		hr.queue_free()
		submitted.emit(false)

# tous les meilleurs scores d'une durée, tous exercices confondus
# (pour le classement général calculé côté client)
func fetch_all(duration: int) -> void:
	if not configured():
		all_received.emit(false, [])
		return
	var hr := HTTPRequest.new()
	hr.timeout = 12.0
	add_child(hr)
	var done := func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		hr.queue_free()
		if code != 200:
			all_received.emit(false, [])
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		all_received.emit(true, data if data is Array else [])
	hr.request_completed.connect(done)
	var url := "%s/rest/v1/leaderboard?duration=eq.%d&select=player,mode,score&limit=100000" % [URL, duration]
	if hr.request(url, _headers()) != OK:
		hr.queue_free()
		all_received.emit(false, [])

func fetch_top(mode: String, duration: int, limit: int = 20) -> void:
	if not configured():
		top_received.emit(false, [])
		return
	var hr := HTTPRequest.new()
	hr.timeout = 8.0
	add_child(hr)
	var done := func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		hr.queue_free()
		if code != 200:
			top_received.emit(false, [])
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		top_received.emit(true, data if data is Array else [])
	hr.request_completed.connect(done)
	var url := "%s/rest/v1/leaderboard?mode=eq.%s&duration=eq.%d&order=score.desc&limit=%d" % [
		URL, mode, duration, limit]
	if hr.request(url, _headers()) != OK:
		hr.queue_free()
		top_received.emit(false, [])

# replay du record perso : upsert sur la clé (mode, duration, player)
func submit_replay(player: String, mode: String, duration: int, score: int, b64: String) -> void:
	if not configured() or b64 == "" or b64.length() > 400000:
		return
	var hr := HTTPRequest.new()
	hr.timeout = 30.0
	add_child(hr)
	hr.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray):
		hr.queue_free())
	var h := _headers()
	h.append("Prefer: return=minimal, resolution=merge-duplicates")
	var body := JSON.stringify({"player": player.substr(0, 20), "mode": mode,
		"duration": duration, "score": score, "data": b64})
	if hr.request(URL + "/rest/v1/replays", h, HTTPClient.METHOD_POST, body) != OK:
		hr.queue_free()

func fetch_replay(mode: String, duration: int, player: String) -> void:
	if not configured():
		replay_received.emit(false, player, "")
		return
	var hr := HTTPRequest.new()
	hr.timeout = 30.0
	add_child(hr)
	var done := func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		hr.queue_free()
		if code != 200:
			replay_received.emit(false, player, "")
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Array and data.size() > 0 and data[0] is Dictionary:
			replay_received.emit(true, player, str(data[0].get("data", "")))
		else:
			replay_received.emit(false, player, "")
	hr.request_completed.connect(done)
	var url := "%s/rest/v1/replays?mode=eq.%s&duration=eq.%d&player=eq.%s&select=player,data" % [
		URL, mode, duration, player.uri_encode()]
	if hr.request(url, _headers()) != OK:
		hr.queue_free()
		replay_received.emit(false, player, "")
