extends Node
## Session management. Host/join over ENet (LAN or Tailscale), or offline single player.
## Every gameplay RPC goes through this autoload so the node path is identical on all peers.

signal players_changed
signal session_started
signal session_ended(reason: String)
signal lobby_map_changed(map_id: String)
signal game_requested(map_id: String)
signal lobby_requested
signal join_failed(reason: String)
signal truck_state_received(peer_id: int, state: Array)
signal winch_force_received(force: Vector3, point: Vector3)
signal objectives_received(state: Dictionary)
signal objective_event_received(peer_id: int, kind: String, data: Dictionary)
signal toast_received(text: String, color: Color)
signal horn_received(peer_id: int, on: bool)

const VERSION := "0.1.0"
const DEFAULT_PORT := 24560
const MAX_PLAYERS := 4
const COLORS: Array[Color] = [Color("e8772e"), Color("3fa7d6"), Color("8cc152"), Color("d9547f")]
const COLOR_NAMES := ["Orange", "Blue", "Green", "Pink"]

var players: Dictionary = {}  # peer_id -> {"name": String, "color": int}
var lobby_map := "forest"
var current_map := ""
var in_game := false
var online := false
var _joining := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_host() -> bool:
	return multiplayer.is_server()


func player_color(peer_id: int) -> Color:
	if players.has(peer_id):
		return COLORS[int(players[peer_id]["color"]) % COLORS.size()]
	return Color.WHITE


func player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return str(players[peer_id]["name"])
	return "Player"


# ---------------------------------------------------------------- session setup

func start_single() -> void:
	_reset()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	players[1] = {"name": Settings.player_name, "color": clampi(Settings.preferred_color, 0, 3)}
	session_started.emit()
	players_changed.emit()


func host(port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	players[1] = {"name": Settings.player_name, "color": clampi(Settings.preferred_color, 0, 3)}
	session_started.emit()
	players_changed.emit()
	return OK


func join(address: String, port: int) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	_joining = true
	return OK


func leave(reason: String = "") -> void:
	var was_in_session := not players.is_empty() or _joining
	_reset()
	if was_in_session:
		session_ended.emit(reason)


func _reset() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	current_map = ""
	online = false
	_joining = false


# ---------------------------------------------------------------- connection events

func _on_connected_to_server() -> void:
	_register.rpc_id(1, Settings.player_name, Settings.preferred_color, VERSION)


func _on_connection_failed() -> void:
	_joining = false
	_reset()
	join_failed.emit("Could not reach the host. Check the address, port and firewall.")


func _on_server_disconnected() -> void:
	leave("The host closed the session.")


func _on_peer_connected(_id: int) -> void:
	pass  # Wait for _register before treating the peer as a player.


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		var who := player_name(id)
		players.erase(id)
		players_changed.emit()
		if is_host():
			_set_players.rpc(players)
			send_toast("%s left" % who, Color(0.9, 0.6, 0.4))


@rpc("any_peer", "reliable")
func _register(pname: String, color: int, version: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_rejected.rpc_id(id, "Version mismatch. Host has %s, you have %s." % [VERSION, version])
		_kick_later(id)
		return
	if players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(id, "That session is full (%d players)." % MAX_PLAYERS)
		_kick_later(id)
		return
	var used := []
	for p in players.values():
		used.append(int(p["color"]))
	var c := clampi(color, 0, 3)
	if c in used:
		for i in 4:
			if not (i in used):
				c = i
				break
	pname = pname.strip_edges().left(16)
	if pname == "":
		pname = "Player %d" % (players.size() + 1)
	players[id] = {"name": pname, "color": c}
	_set_players.rpc(players)
	players_changed.emit()
	_welcome.rpc_id(id, lobby_map, current_map, in_game)
	send_toast("%s joined" % pname, Color(0.6, 0.9, 0.6))


func _kick_later(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	_joining = false
	_reset()
	join_failed.emit(reason)


@rpc("authority", "reliable")
func _set_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


@rpc("authority", "reliable")
func _welcome(lmap: String, cmap: String, ingame: bool) -> void:
	_joining = false
	lobby_map = lmap
	session_started.emit()
	players_changed.emit()
	if ingame:
		current_map = cmap
		in_game = true
		game_requested.emit(cmap)


# ---------------------------------------------------------------- lobby / game flow

func set_lobby_map(map_id: String) -> void:
	if is_host():
		_lobby_map.rpc(map_id)


@rpc("authority", "call_local", "reliable")
func _lobby_map(map_id: String) -> void:
	lobby_map = map_id
	lobby_map_changed.emit(map_id)


func start_game(map_id: String) -> void:
	if is_host():
		_start.rpc(map_id)


@rpc("authority", "call_local", "reliable")
func _start(map_id: String) -> void:
	lobby_map = map_id
	current_map = map_id
	in_game = true
	game_requested.emit(map_id)


func return_to_lobby() -> void:
	if is_host():
		_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _lobby() -> void:
	in_game = false
	current_map = ""
	lobby_requested.emit()


# ---------------------------------------------------------------- gameplay traffic

func send_truck_state(state: Array) -> void:
	if online:
		_truck_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _truck_state(state: Array) -> void:
	truck_state_received.emit(multiplayer.get_remote_sender_id(), state)


func send_winch_force(target: int, force: Vector3, point: Vector3) -> void:
	if online and players.has(target) and target != my_id():
		_winch_force.rpc_id(target, force, point)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _winch_force(force: Vector3, point: Vector3) -> void:
	winch_force_received.emit(force, point)


func send_horn(on: bool) -> void:
	if online:
		_horn.rpc(on)


@rpc("any_peer", "call_remote", "reliable")
func _horn(on: bool) -> void:
	horn_received.emit(multiplayer.get_remote_sender_id(), on)


func broadcast_objectives(state: Dictionary) -> void:
	if is_host():
		_objectives.rpc(state)


@rpc("authority", "call_local", "reliable")
func _objectives(state: Dictionary) -> void:
	objectives_received.emit(state)


func report_event(kind: String, data: Dictionary = {}) -> void:
	_objective_event.rpc_id(1, kind, data)


@rpc("any_peer", "call_local", "reliable")
func _objective_event(kind: String, data: Dictionary) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = my_id()
	objective_event_received.emit(sender, kind, data)


func send_toast(text: String, color: Color = Color.WHITE) -> void:
	if is_host():
		_toast.rpc(text, color)


@rpc("authority", "call_local", "reliable")
func _toast(text: String, color: Color) -> void:
	toast_received.emit(text, color)


# ---------------------------------------------------------------- helpers

static func local_addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		out.append(s)
	out.sort_custom(func(x, y): return _addr_rank(x) < _addr_rank(y))
	return out


static func _addr_rank(a: String) -> int:
	if a.begins_with("100."):
		return 0  # Tailscale (CGNAT range)
	if a.begins_with("192.168.") or a.begins_with("10."):
		return 1
	return 2


static func is_tailscale(a: String) -> bool:
	if not a.begins_with("100."):
		return false
	var parts := a.split(".")
	return parts.size() == 4 and int(parts[1]) >= 64 and int(parts[1]) <= 127
