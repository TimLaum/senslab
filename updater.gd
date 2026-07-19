class_name Updater
extends Node
# Mise à jour automatique via les releases GitHub.
# check() compare le tag de la dernière release à VERSION ;
# install() télécharge le nouvel exe puis se remplace via un .bat
# (un exe Windows ne peut pas s'écraser lui-même pendant qu'il tourne).

const REPO := "TimLaum/senslab"
const VERSION := "1.6"

signal update_available(tag: String)
signal progress(pct: int)
signal failed(msg: String)

var latest_tag := ""
var _asset_url := ""
var _dl: HTTPRequest

func check() -> void:
	var hr := HTTPRequest.new()
	hr.timeout = 10.0
	add_child(hr)
	var done := func(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		hr.queue_free()
		if code != 200:
			return
		var d = JSON.parse_string(body.get_string_from_utf8())
		if not (d is Dictionary):
			return
		latest_tag = str(d.get("tag_name", ""))
		if not _newer(latest_tag, VERSION):
			return
		for a in d.get("assets", []):
			if str(a.get("name", "")) == "SensLab.exe":
				_asset_url = str(a.get("browser_download_url", ""))
		if _asset_url != "":
			update_available.emit(latest_tag)
	hr.request_completed.connect(done)
	hr.request("https://api.github.com/repos/%s/releases/latest" % REPO,
		PackedStringArray(["User-Agent: SensLab", "Accept: application/vnd.github+json"]))

static func _newer(tag: String, cur: String) -> bool:
	var a := tag.trim_prefix("v").split(".")
	var b := cur.trim_prefix("v").split(".")
	for i in maxi(a.size(), b.size()):
		var ai := int(a[i]) if i < a.size() else 0
		var bi := int(b[i]) if i < b.size() else 0
		if ai != bi:
			return ai > bi
	return false

# false quand on tourne depuis l'éditeur Godot : rien à remplacer
func can_install() -> bool:
	return OS.get_executable_path().get_file().to_lower().begins_with("senslab")

func install() -> void:
	var exe := OS.get_executable_path()
	var newf := exe.get_base_dir().path_join("SensLab_update.exe")
	_dl = HTTPRequest.new()
	_dl.timeout = 600.0
	add_child(_dl)
	_dl.download_file = newf
	var done := func(_result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		var dl := _dl
		_dl = null
		dl.queue_free()
		if code != 200:
			failed.emit("téléchargement échoué (HTTP %d)" % code)
			return
		_swap_and_restart(exe, newf)
	_dl.request_completed.connect(done)
	if _dl.request(_asset_url, PackedStringArray(["User-Agent: SensLab"])) != OK:
		_dl.queue_free()
		_dl = null
		failed.emit("impossible de démarrer le téléchargement")

func _process(_delta: float) -> void:
	if _dl != null and _dl.get_body_size() > 0:
		progress.emit(int(_dl.get_downloaded_bytes() * 100.0 / _dl.get_body_size()))

func _swap_and_restart(exe: String, newf: String) -> void:
	var exe_w := exe.replace("/", "\\")
	var new_w := newf.replace("/", "\\")
	var bat := exe.get_base_dir().path_join("senslab_update.bat")
	var f := FileAccess.open(bat, FileAccess.WRITE)
	if f == null:
		failed.emit("impossible d'écrire le script de mise à jour")
		return
	f.store_string("@echo off\r\n"
		+ ":wait\r\n"
		+ "timeout /t 1 /nobreak >nul\r\n"
		+ "move /y \"%s\" \"%s\" >nul 2>&1 || goto wait\r\n" % [new_w, exe_w]
		+ "start \"\" \"%s\"\r\n" % exe_w
		+ "del \"%~f0\"\r\n")
	f.close()
	OS.create_process("cmd.exe", ["/c", bat.replace("/", "\\")])
	get_tree().quit()
