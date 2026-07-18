class_name Room
extends Node
# Rooms de défi multijoueur (1v1v1…) via Supabase REST.
# Tout est piloté par les clients ; l'heure serveur (RPC room_start /
# server_now) sert de référence pour lancer chaque round en simultané.

signal state_received(ok: bool, data: Dictionary)
signal now_received(epoch: float)
signal op_done(op: String, ok: bool)

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: " + Leaderboard.KEY,
		"Authorization: Bearer " + Leaderboard.KEY,
		"Content-Type: application/json",
		"Prefer: return=minimal, resolution=merge-duplicates",
	])

func _call_api(method: int, path: String, body: String, cb: Callable) -> void:
	var hr := HTTPRequest.new()
	hr.timeout = 8.0
	add_child(hr)
	hr.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, bytes: PackedByteArray):
		hr.queue_free()
		cb.call(code, bytes))
	if hr.request(Leaderboard.URL + path, _headers(), method, body) != OK:
		hr.queue_free()
		cb.call(0, PackedByteArray())

# décalage d'horloge : epoch serveur via RPC
func srv_now() -> void:
	_call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/server_now", "{}",
		func(code: int, b: PackedByteArray):
			if code == 200:
				now_received.emit(b.get_string_from_utf8().to_float()))

func create(code: String, host: String, duration: int, open_pl: bool) -> void:
	var room := {"id": code, "host": host, "duration": duration, "open_playlist": open_pl}
	_call_api(HTTPClient.METHOD_POST, "/rest/v1/rooms", JSON.stringify(room),
		func(c: int, _b: PackedByteArray):
			if c < 200 or c >= 300:
				op_done.emit("create", false)
				return
			_call_api(HTTPClient.METHOD_POST, "/rest/v1/room_players",
				JSON.stringify({"room_id": code, "player": host}),
				func(c2: int, _b2: PackedByteArray):
					op_done.emit("create", c2 >= 200 and c2 < 300)))

func join(code: String, player: String) -> void:
	_call_api(HTTPClient.METHOD_GET, "/rest/v1/rooms?id=eq.%s&select=id" % code, "",
		func(c: int, b: PackedByteArray):
			var arr = JSON.parse_string(b.get_string_from_utf8()) if c == 200 else null
			if not (arr is Array) or (arr as Array).is_empty():
				op_done.emit("join", false)
				return
			_call_api(HTTPClient.METHOD_POST, "/rest/v1/room_players",
				JSON.stringify({"room_id": code, "player": player}),
				func(c2: int, _b2: PackedByteArray):
					op_done.emit("join", c2 >= 200 and c2 < 300)))

func leave(code: String, player: String) -> void:
	_call_api(HTTPClient.METHOD_DELETE,
		"/rest/v1/room_players?room_id=eq.%s&player=eq.%s" % [code, player.uri_encode()], "",
		func(_c: int, _b: PackedByteArray):
			op_done.emit("leave", true))

# état complet de la room en une requête (imbrication PostgREST)
func fetch(code: String) -> void:
	var q := "/rest/v1/rooms?id=eq.%s&select=*,room_modes(*),room_players(*),room_scores(*)&room_modes.order=ord.asc" % code
	_call_api(HTTPClient.METHOD_GET, q, "",
		func(c: int, b: PackedByteArray):
			if c != 200:
				state_received.emit(false, {})
				return
			var arr = JSON.parse_string(b.get_string_from_utf8())
			if arr is Array and (arr as Array).size() > 0 and arr[0] is Dictionary:
				state_received.emit(true, arr[0])
			else:
				state_received.emit(false, {}))

func add_mode(code: String, mode: String, by: String, ord: int) -> void:
	_call_api(HTTPClient.METHOD_POST, "/rest/v1/room_modes",
		JSON.stringify({"room_id": code, "mode": mode, "added_by": by, "ord": ord}),
		func(c: int, _b: PackedByteArray):
			op_done.emit("addmode", c >= 200 and c < 300))

# lance le round : le serveur fixe start_epoch = now() + 6 s pour tout le monde
func start(code: String, round_i: int) -> void:
	_call_api(HTTPClient.METHOD_POST, "/rest/v1/rpc/room_start",
		JSON.stringify({"p_room": code, "p_round": round_i}),
		func(c: int, _b: PackedByteArray):
			op_done.emit("start", c == 200))

func finish(code: String) -> void:
	_call_api(HTTPClient.METHOD_PATCH, "/rest/v1/rooms?id=eq.%s" % code,
		JSON.stringify({"state": "done"}),
		func(c: int, _b: PackedByteArray):
			op_done.emit("finish", c >= 200 and c < 300))

func submit(code: String, player: String, round_i: int, score: int) -> void:
	_call_api(HTTPClient.METHOD_POST, "/rest/v1/room_scores",
		JSON.stringify({"room_id": code, "player": player, "round_i": round_i, "score": score}),
		func(c: int, _b: PackedByteArray):
			op_done.emit("score", c >= 200 and c < 300))
