extends Node2D

# Crown & Banner — Phase 1. A small, data-driven, touch-first field battle.
# All artwork is drawn from original pixel-style primitives so the prototype has no external assets.

const VIEW_SIZE := Vector2(1280, 720)
const FIELD := Rect2(0, 78, 1280, 494)
const HUD_TOP := 78.0
const HUD_BOTTOM := 572.0
const SAVE_FILE := "user://battle_autosave.json"
const PALETTE := {
	"ink": Color("202723"),
	"panel": Color("252c29"),
	"panel_edge": Color("665f4e"),
	"paper": Color("ddd0ae"),
	"muted": Color("a99e84"),
	"gold": Color("d1b36d"),
	"grass": Color("657757"),
	"grass_light": Color("7e8962"),
	"grass_dark": Color("4d624c"),
	"mud": Color("76664e"),
	"red": Color("a65348"),
	"blue": Color("7994a0"),
	"health": Color("9fac78"),
	"morale": Color("c4a765"),
	"white": Color("eee7d4")
}

var units: Array[Dictionary] = []
var selected_id := ""
var battle_time := 0.0
var game_over := false
var victory := false
var paused := false
var sim_speed := 1.0
var zoom := 1.0
var camera_offset := Vector2.ZERO
var touch_positions: Dictionary = {}
var drag_id := -1
var drag_start := Vector2.ZERO
var drag_current := Vector2.ZERO
var dragging_unit := false
var rng := RandomNumberGenerator.new()
var terrain_marks: Array[Dictionary] = []
var ambient_dust: Array[Vector2] = []
var help_message := "Tap a regiment, then tap the field to move. Choose an order below."
var message_timer := 6.0
var match_seed := 39017
var battle_result := ""
var ignore_pointer_up := false


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	rng.seed = match_seed
	_make_terrain()
	_start_battle()
	set_process(true)


func _start_battle() -> void:
	units.clear()
	selected_id = ""
	game_over = false
	victory = false
	paused = false
	battle_time = 0.0
	battle_result = ""
	var parsed := JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))
	if not parsed is Dictionary or not parsed.has("units"):
		push_error("Unable to read data/units.json")
		return
	var templates: Array = parsed["units"]
	for i in range(templates.size()):
		var unit: Dictionary = templates[i].duplicate(true)
		unit["team"] = 0 if i < 4 else 1
		unit["pos"] = _formation_position(i)
		unit["target_pos"] = unit["pos"]
		unit["order"] = "hold" if i < 4 else "attack"
		unit["morale_now"] = float(unit["morale"])
		unit["alive"] = true
		unit["cooldown"] = 0.6 + float(i % 3) * 0.35
		unit["charge_time"] = 0.0
		unit["flash"] = 0.0
		unit["losses"] = 0
		units.append(unit)
	selected_id = "levy_spears"
	help_message = "The Grey March meets the Red Fen. Your orders decide the field."
	message_timer = 5.0
	queue_redraw()


func _formation_position(index: int) -> Vector2:
	var friendly := index < 4
	var row := index % 4
	if friendly:
		return Vector2(210.0 + float(row % 2) * 74.0, 190.0 + float(row) * 91.0)
	return Vector2(1060.0 - float(row % 2) * 70.0, 190.0 + float(row) * 91.0)


func _make_terrain() -> void:
	terrain_marks.clear()
	ambient_dust.clear()
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = 88202
	for i in range(210):
		var p := Vector2(local_rng.randf_range(24, 1256), local_rng.randf_range(92, 566))
		terrain_marks.append({"pos": p, "kind": i % 9, "shade": local_rng.randf_range(0.0, 1.0)})
	for i in range(26):
		ambient_dust.append(
			Vector2(local_rng.randf_range(0, 1280), local_rng.randf_range(100, 565))
		)


func _process(delta: float) -> void:
	message_timer = maxf(0.0, message_timer - delta)
	if paused or game_over:
		queue_redraw()
		return
	var step := delta * sim_speed
	battle_time += step
	for i in range(units.size()):
		_simulate_unit(i, step)
	_check_victory()
	queue_redraw()


func _simulate_unit(index: int, delta: float) -> void:
	var unit: Dictionary = units[index]
	if not unit["alive"]:
		return
	unit["cooldown"] = maxf(0.0, float(unit["cooldown"]) - delta)
	unit["charge_time"] = maxf(0.0, float(unit["charge_time"]) - delta)
	unit["flash"] = maxf(0.0, float(unit["flash"]) - delta * 2.5)
	var pos: Vector2 = unit["pos"]
	var nearest: Dictionary = _nearest_enemy(unit)
	if float(unit["morale_now"]) <= 17.0:
		unit["order"] = "rout"
	if unit["order"] == "rout":
		if not nearest.is_empty():
			var flee_dir: Vector2 = (pos - nearest["pos"]).normalized()
			pos += flee_dir * float(unit["speed"]) * delta * 1.1
		if (
			float(unit["morale_now"]) > 42.0
			and (nearest.is_empty() or pos.distance_to(nearest["pos"]) > 170.0)
		):
			unit["order"] = "hold"
		unit["pos"] = _clamp_world(pos)
		return

	if unit["order"] == "move":
		var destination: Vector2 = unit["target_pos"]
		var distance := pos.distance_to(destination)
		if distance > 9.0:
			pos += (destination - pos).normalized() * float(unit["speed"]) * delta
			unit["pos"] = _clamp_world(pos)
			return
		unit["order"] = "hold"

	var should_engage := unit["team"] == 1 or unit["order"] in ["attack", "charge", "fire"]
	if (
		unit["order"] == "hold"
		and not nearest.is_empty()
		and pos.distance_to(nearest["pos"]) < 68.0
	):
		should_engage = true
	if not should_engage or nearest.is_empty():
		return
	var target_pos: Vector2 = nearest["pos"]
	var dist := pos.distance_to(target_pos)
	var ranged := int(unit["range"]) > 0
	var effective_range := float(unit["range"]) if ranged else 28.0
	if ranged and int(unit["ammo"]) <= 0:
		effective_range = 28.0
		ranged = false
	if dist > effective_range:
		var speed_mult := 1.0
		if unit["order"] == "charge" and float(unit["charge_time"]) == 0.0:
			speed_mult = 1.75
			unit["charge_time"] = 1.4
		pos += (target_pos - pos).normalized() * float(unit["speed"]) * speed_mult * delta
		unit["pos"] = _clamp_world(pos)
		return
	if float(unit["cooldown"]) > 0.0:
		return
	var armor := float(nearest["armor"])
	var attack := float(unit["attack"])
	var charge_bonus := float(unit["charge"]) if float(unit["charge_time"]) > 0.0 else 0.0
	var damage := 1
	if ranged:
		var hit_chance := clampf(float(unit["accuracy"]) / 100.0, 0.25, 0.9)
		if rng.randf() <= hit_chance:
			damage = rng.randi_range(1, 3) + int(attack > armor + 5.0)
		unit["ammo"] = int(unit["ammo"]) - 1
		unit["cooldown"] = 1.15
	else:
		damage = clampi(
			int(round((attack + charge_bonus * 0.26 - armor * 0.35) * rng.randf_range(0.18, 0.32))),
			1,
			5
		)
		unit["cooldown"] = 0.9
	if damage > 0:
		nearest["count"] = maxi(0, int(nearest["count"]) - damage)
		nearest["losses"] = int(nearest["losses"]) + damage
		nearest["morale_now"] = maxf(
			0.0,
			(
				float(nearest["morale_now"])
				- float(damage) * 0.62
				- (0.7 if unit["order"] == "charge" else 0.0)
			)
		)
		nearest["flash"] = 0.65
		if int(nearest["count"]) == 0:
			nearest["alive"] = false
			nearest["morale_now"] = 0.0
			unit["morale_now"] = minf(100.0, float(unit["morale_now"]) + 7.0)
			_set_message(str(unit["name"]) + " breaks the enemy line!")


func _nearest_enemy(unit: Dictionary) -> Dictionary:
	var target_id := str(unit.get("target_id", ""))
	if target_id != "":
		for other in units:
			if other["id"] == target_id and other["alive"] and other["team"] != unit["team"]:
				return other
		unit.erase("target_id")
	var best: Dictionary = {}
	var best_dist := INF
	for other in units:
		if not other["alive"] or other["team"] == unit["team"]:
			continue
		var distance: float = unit["pos"].distance_to(other["pos"])
		if distance < best_dist:
			best_dist = distance
			best = other
	return best


func _clamp_world(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 70.0, 1210.0), clampf(pos.y, 112.0, 548.0))


func _check_victory() -> void:
	var living := [false, false]
	var routs := [true, true]
	for unit in units:
		if unit["alive"]:
			living[int(unit["team"])] = true
			if float(unit["morale_now"]) > 17.0:
				routs[int(unit["team"])] = false
	if not living[1] or routs[1]:
		game_over = true
		victory = true
		battle_result = "VICTORY — The Fen host gives way"
	elif not living[0] or routs[0]:
		game_over = true
		victory = false
		battle_result = "DEFEAT — The Grey March is broken"
	if game_over:
		_write_autosave()


func _set_message(text: String) -> void:
	help_message = text
	message_timer = 3.2


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			touch_positions[touch.index] = touch.position
			if touch_positions.size() == 1:
				_pointer_down(touch.position, touch.index)
		else:
			touch_positions.erase(touch.index)
			_pointer_up(touch.position, touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if touch_positions.size() >= 2:
			var ids: Array = touch_positions.keys()
			var old_a: Vector2 = touch_positions[ids[0]]
			var old_b: Vector2 = touch_positions[ids[1]]
			touch_positions[drag.index] = drag.position
			var new_a: Vector2 = touch_positions[ids[0]]
			var new_b: Vector2 = touch_positions[ids[1]]
			var old_distance := old_a.distance_to(old_b)
			var new_distance := new_a.distance_to(new_b)
			if old_distance > 1.0:
				var old_zoom := zoom
				zoom = clampf(zoom * new_distance / old_distance, 0.78, 1.3)
				var old_center := (old_a + old_b) * 0.5
				var new_center := (new_a + new_b) * 0.5
				camera_offset = new_center - (old_center - camera_offset) * (zoom / old_zoom)
			queue_redraw()
		else:
			touch_positions[drag.index] = drag.position
			drag_current = drag.position
	elif event is InputEventMouseButton and event.pressed:
		_pointer_down(event.position, 0)
	elif event is InputEventMouseButton and not event.pressed:
		_pointer_up(event.position, 0)
	elif event is InputEventMouseMotion and dragging_unit:
		drag_current = event.position


func _pointer_down(pos: Vector2, pointer_id: int) -> void:
	ignore_pointer_up = false
	drag_id = pointer_id
	drag_start = pos
	drag_current = pos
	dragging_unit = false
	if game_over:
		ignore_pointer_up = true
		if Rect2(490, 415, 300, 70).has_point(pos):
			_start_battle()
		return
	if _handle_ui(pos):
		return
	if not _in_field(pos):
		return
	var world := _screen_to_world(pos)
	var hit := _unit_at(world)
	if not hit.is_empty() and int(hit["team"]) == 0:
		selected_id = str(hit["id"])
		dragging_unit = true
		queue_redraw()


func _pointer_up(pos: Vector2, pointer_id: int) -> void:
	if ignore_pointer_up:
		ignore_pointer_up = false
		return
	if pointer_id != drag_id or game_over:
		return
	if dragging_unit and drag_start.distance_to(pos) > 18.0 and _in_field(pos):
		_issue_move(_screen_to_world(pos))
	elif _in_field(pos) and drag_start.distance_to(pos) < 24.0:
		var world := _screen_to_world(pos)
		var hit := _unit_at(world)
		if not hit.is_empty() and int(hit["team"]) == 0:
			selected_id = str(hit["id"])
		elif not hit.is_empty() and int(hit["team"]) == 1:
			_issue_attack(str(hit["id"]))
		elif selected_id != "":
			_issue_move(world)
	dragging_unit = false
	queue_redraw()


func _handle_ui(pos: Vector2) -> bool:
	if pos.y < 76.0:
		if Rect2(1016, 12, 72, 52).has_point(pos):
			paused = not paused
		elif Rect2(1096, 12, 72, 52).has_point(pos):
			sim_speed = 0.5
		elif Rect2(1176, 12, 88, 52).has_point(pos):
			sim_speed = 1.0 if sim_speed == 2.0 else 2.0
		return true
	if pos.y >= 580.0:
		for i in range(4):
			var card := Rect2(18 + i * 151, 590, 143, 110)
			if card.has_point(pos):
				selected_id = str(units[i]["id"])
				return true
		var button_x := [662.0, 806.0, 950.0, 1094.0]
		var actions := ["attack", "hold", "charge", "fire"]
		for i in range(4):
			if Rect2(button_x[i], 590, 132, 50).has_point(pos):
				_issue_order(actions[i])
				return true
		if Rect2(662, 648, 132, 50).has_point(pos):
			_rally_selected()
		return true
	return false


func _in_field(pos: Vector2) -> bool:
	return FIELD.has_point(pos)


func _screen_to_world(pos: Vector2) -> Vector2:
	return (pos - camera_offset) / zoom


func _world_to_screen(pos: Vector2) -> Vector2:
	return pos * zoom + camera_offset


func _unit_at(world: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := 46.0 / zoom
	for unit in units:
		if not unit["alive"]:
			continue
		var radius := 34.0 if unit["class"] == "cavalry" else 28.0
		var distance: float = world.distance_to(unit["pos"])
		if distance < maxf(radius, best_dist):
			best = unit
			best_dist = distance
	return best


func _get_selected() -> Dictionary:
	for unit in units:
		if unit["id"] == selected_id:
			return unit
	return {}


func _issue_move(destination: Vector2) -> void:
	var unit := _get_selected()
	if unit.is_empty() or not unit["alive"]:
		return
	unit.erase("target_id")
	unit["order"] = "move"
	unit["target_pos"] = _clamp_world(destination)
	_set_message(str(unit["name"]) + " moving to your marker")


func _issue_attack(target_id: String) -> void:
	var unit := _get_selected()
	if unit.is_empty() or not unit["alive"]:
		return
	unit["order"] = "attack"
	unit["target_id"] = target_id
	_set_message(str(unit["name"]) + " advancing to engage")


func _issue_order(order: String) -> void:
	var unit := _get_selected()
	if unit.is_empty() or not unit["alive"]:
		return
	if order == "attack":
		unit.erase("target_id")
	unit["order"] = order
	if order == "attack":
		_set_message(str(unit["name"]) + " will engage the nearest foe")
	elif order == "hold":
		_set_message(str(unit["name"]) + " holds its ground")
	elif order == "charge":
		unit["charge_time"] = 0.0
		_set_message("Charge! " + str(unit["name"]) + " surges forward")
	else:
		if int(unit["range"]) == 0:
			unit["order"] = "attack"
			_set_message("Only missile troops can use fire-at-will")
		else:
			_set_message(str(unit["name"]) + " looses arrows at will")


func _rally_selected() -> void:
	var unit := _get_selected()
	if unit.is_empty():
		return
	unit["morale_now"] = minf(100.0, float(unit["morale_now"]) + 24.0)
	if unit["order"] == "rout":
		unit["order"] = "hold"
	_set_message(str(unit["name"]) + " rallies — morale restored")


func _write_autosave() -> void:
	var snapshot := {
		"seed": match_seed, "time": battle_time, "victory": victory, "result": battle_result
	}
	var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot))


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), PALETTE["ink"])
	_draw_battlefield()
	_draw_units(font)
	_draw_top_hud(font)
	_draw_bottom_hud(font)
	_draw_feedback(font)
	if paused and not game_over:
		_draw_pause_overlay(font)
	if game_over:
		_draw_result_overlay(font)


func _draw_battlefield() -> void:
	draw_rect(FIELD, Color("647653"))
	# Broad, low-contrast bands keep the field legible beneath the small troops.
	draw_rect(Rect2(0, 79, 1280, 493), Color(0.20, 0.30, 0.20, 0.12))
	for mark in terrain_marks:
		var p: Vector2 = _world_to_screen(mark["pos"])
		var shade: float = mark["shade"]
		var color := Color("89906a") if shade > 0.72 else Color("556b4d")
		var size := 3.0 if int(mark["kind"]) % 3 else 5.0
		draw_rect(Rect2(p, Vector2(size, size) * zoom), color)
	# Old cart track: a pale broken ribbon across the center of the field.
	var track := PackedVector2Array()
	for i in range(15):
		var x := 390.0 + float(i) * 35.0
		var y := 130.0 + sin(float(i) * 0.45) * 47.0
		track.append(_world_to_screen(Vector2(x, y)))
	draw_polyline(track, Color(0.69, 0.63, 0.47, 0.34), 16.0 * zoom, true)
	for i in range(5):
		var x := 515.0 + i * 58.0
		var y := 178.0 + (i % 2) * 58.0
		_draw_tree(Vector2(x, y))
	for i in range(4):
		_draw_rock(Vector2(725.0 + i * 29.0, 402.0 + (i % 2) * 11.0))
	# Soft ridge at the far edge and a low shadowed horizon.
	draw_rect(Rect2(0, 78, 1280, 12), Color("394c3e"))
	draw_rect(Rect2(0, 565, 1280, 8), Color("354639"))
	draw_rect(FIELD, Color(0, 0, 0, 0), false, 2)


func _draw_tree(world_pos: Vector2) -> void:
	var p := _world_to_screen(world_pos)
	var s := zoom
	draw_rect(Rect2(p + Vector2(-4, 0) * s, Vector2(9, 20) * s), Color("4d4937"))
	draw_rect(Rect2(p + Vector2(-15, -16) * s, Vector2(31, 20) * s), Color("3e5942"))
	draw_rect(Rect2(p + Vector2(-11, -23) * s, Vector2(22, 12) * s), Color("56704b"))
	draw_rect(Rect2(p + Vector2(-8, -20) * s, Vector2(6, 4) * s), Color("81906a"))


func _draw_rock(world_pos: Vector2) -> void:
	var p := _world_to_screen(world_pos)
	var s := zoom
	draw_rect(Rect2(p + Vector2(-10, -5) * s, Vector2(20, 12) * s), Color("554f43"))
	draw_rect(Rect2(p + Vector2(-6, -9) * s, Vector2(12, 6) * s), Color("8b816b"))
	draw_rect(Rect2(p + Vector2(-4, -7) * s, Vector2(4, 2) * s), Color("b0a387"))


func _draw_units(font: Font) -> void:
	for unit in units:
		if not unit["alive"]:
			continue
		var center: Vector2 = _world_to_screen(unit["pos"])
		var selected := unit["id"] == selected_id
		var body_color := Color(str(unit["color"]))
		var trim_color := Color(str(unit["accent"]))
		var alive_ratio := clampf(
			float(unit["count"]) / float(unit["count"] + unit["losses"]), 0.25, 1.0
		)
		draw_rect(
			Rect2(center + Vector2(-39, 20) * zoom, Vector2(78, 5) * zoom),
			Color(0.10, 0.12, 0.10, 0.34)
		)
		if selected:
			draw_arc(center, 43.0 * zoom, 0, TAU, 48, PALETTE["gold"], 2.2 * zoom, true)
			_draw_order_marker(unit, center, font)
		var people := maxi(5, int(round(20.0 * alive_ratio)))
		for soldier in range(people):
			var col := soldier % 5
			var row := soldier / 5
			var local := Vector2((float(col) - 2.0) * 12.0, (float(row) - 1.5) * 11.0)
			_draw_soldier(
				center + local * zoom,
				str(unit["class"]),
				body_color,
				trim_color,
				int(unit["team"]) == 0,
				soldier,
				zoom
			)
		_draw_banner(center, int(unit["team"]), trim_color, zoom)
		var label := str(unit["name"])
		var label_width := 128.0 * zoom
		draw_string(
			font,
			center + Vector2(-label_width * 0.5, 47.0 * zoom),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			label_width,
			11,
			Color("f0e5c7")
		)
		var bar_width := 52.0 * zoom
		var bar_y := center.y + 52.0 * zoom
		draw_rect(Rect2(center.x - bar_width * 0.5, bar_y, bar_width, 4.0 * zoom), Color("302d27"))
		draw_rect(
			Rect2(
				center.x - bar_width * 0.5,
				bar_y,
				bar_width * float(unit["morale_now"]) / 100.0,
				4.0 * zoom
			),
			PALETTE["morale"] if float(unit["morale_now"]) > 17.0 else PALETTE["red"]
		)
		if float(unit["flash"]) > 0.0:
			draw_circle(center, 33.0 * zoom, Color(1.0, 0.80, 0.53, float(unit["flash"]) * 0.20))


func _draw_soldier(
	p: Vector2, kind: String, cloth: Color, trim: Color, friendly: bool, number: int, scale: float
) -> void:
	var s := scale
	var shadow := Color(0.13, 0.15, 0.12, 0.45)
	draw_rect(Rect2(p + Vector2(-4, 4) * s, Vector2(9, 3) * s), shadow)
	if kind == "cavalry":
		# Compact horse silhouette with rider, deliberately built on the same pixel grid.
		draw_rect(Rect2(p + Vector2(-6, -1) * s, Vector2(13, 7) * s), Color("594d3d"))
		draw_rect(Rect2(p + Vector2(2, -4) * s, Vector2(5, 5) * s), Color("76634c"))
		draw_rect(Rect2(p + Vector2(-4, 5) * s, Vector2(2, 5) * s), Color("3c3931"))
		draw_rect(Rect2(p + Vector2(3, 5) * s, Vector2(2, 5) * s), Color("3c3931"))
		draw_rect(Rect2(p + Vector2(-2, -8) * s, Vector2(7, 7) * s), cloth)
		draw_rect(Rect2(p + Vector2(-1, -12) * s, Vector2(5, 4) * s), trim)
	else:
		draw_rect(Rect2(p + Vector2(-3, 2) * s, Vector2(2, 6) * s), Color("34352f"))
		draw_rect(Rect2(p + Vector2(2, 2) * s, Vector2(2, 6) * s), Color("34352f"))
		draw_rect(Rect2(p + Vector2(-4, -5) * s, Vector2(9, 8) * s), cloth)
		draw_rect(Rect2(p + Vector2(-3, -9) * s, Vector2(7, 5) * s), trim)
		draw_rect(Rect2(p + Vector2(-2, -13) * s, Vector2(5, 5) * s), Color("c4a889"))
		draw_rect(Rect2(p + Vector2(-3, -14) * s, Vector2(7, 3) * s), Color("77776c"))
		if kind == "spears":
			draw_rect(Rect2(p + Vector2(5, -17) * s, Vector2(1.4, 20) * s), Color("c1ad81"))
			draw_rect(Rect2(p + Vector2(4, -18) * s, Vector2(3, 4) * s), Color("a9a58f"))
		elif kind == "ranged":
			draw_rect(Rect2(p + Vector2(5, -7) * s, Vector2(2, 11) * s), Color("a47a4e"))
		else:
			draw_rect(Rect2(p + Vector2(5, -6) * s, Vector2(2, 11) * s), Color("b8b5a7"))
		if friendly and number % 3 == 0:
			draw_rect(Rect2(p + Vector2(-5, -4) * s, Vector2(3, 6) * s), Color("b8ad8d"))


func _draw_banner(center: Vector2, team: int, trim: Color, scale: float) -> void:
	var s := scale
	var x := center.x + 30.0 * s
	var y := center.y - 36.0 * s
	draw_rect(Rect2(x, y, 2.0 * s, 33.0 * s), Color("c8b994"))
	var banner := Color("718b8e") if team == 0 else Color("994e43")
	draw_rect(Rect2(x + 2.0 * s, y + 2.0 * s, 13.0 * s, 10.0 * s), banner)
	draw_rect(Rect2(x + 4.0 * s, y + 4.0 * s, 4.0 * s, 6.0 * s), trim)
	draw_rect(Rect2(x + 2.0 * s, y + 12.0 * s, 3.0 * s, 3.0 * s), banner)


func _draw_order_marker(unit: Dictionary, center: Vector2, font: Font) -> void:
	if unit["order"] == "move":
		var target: Vector2 = _world_to_screen(unit["target_pos"])
		draw_arc(target, 10.0 * zoom, 0, TAU, 24, PALETTE["gold"], 2.0 * zoom)
		draw_line(center, target, Color(0.94, 0.80, 0.47, 0.45), 1.4 * zoom, true)
	elif unit["order"] == "rout":
		draw_string(
			font,
			center + Vector2(-12, -43) * zoom,
			"ROUT",
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			10,
			PALETTE["red"]
		)


func _draw_top_hud(font: Font) -> void:
	draw_rect(Rect2(0, 0, 1280, 78), Color("202723"))
	draw_rect(Rect2(0, 74, 1280, 4), Color("9b8758"))
	draw_rect(Rect2(18, 15, 42, 42), Color("9d794f"))
	draw_rect(Rect2(23, 20, 32, 32), Color("343a34"))
	draw_string(font, Vector2(30, 43), "C", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, PALETTE["gold"])
	draw_string(
		font, Vector2(72, 31), "CROWN & BANNER", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, PALETTE["paper"]
	)
	draw_string(
		font,
		Vector2(72, 52),
		"ASHES OF VEYR  /  FIELD TEST",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		PALETTE["muted"]
	)
	draw_rect(Rect2(371, 18, 1, 42), PALETTE["panel_edge"])
	draw_string(
		font,
		Vector2(390, 32),
		"HIGH SUMMER  •  DAY 1",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		PALETTE["gold"]
	)
	var left_strength := _team_strength(0)
	var right_strength := _team_strength(1)
	draw_string(
		font,
		Vector2(390, 52),
		"GREY MARCH  " + str(left_strength) + "   VS   " + str(right_strength) + "  RED FEN",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		PALETTE["paper"]
	)
	draw_rect(Rect2(770, 21, 174, 13), Color("353a32"))
	var total := maxi(1, left_strength + right_strength)
	draw_rect(Rect2(770, 21, 174.0 * float(left_strength) / float(total), 13), Color("788b80"))
	draw_rect(
		Rect2(
			770 + 174.0 * float(left_strength) / float(total),
			21,
			174.0 * float(right_strength) / float(total),
			13
		),
		Color("98584a")
	)
	draw_string(
		font,
		Vector2(770, 52),
		"FIELD ADVANTAGE",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		PALETTE["muted"]
	)
	_draw_header_button(font, Rect2(1016, 12, 72, 52), "Ⅱ" if not paused else "▶", "PAUSE")
	_draw_header_button(font, Rect2(1096, 12, 72, 52), "½×", "SLOW")
	_draw_header_button(font, Rect2(1176, 12, 88, 52), "1×" if sim_speed != 2.0 else "2×", "SPEED")


func _team_strength(team: int) -> int:
	var total := 0
	for unit in units:
		if int(unit["team"]) == team and unit["alive"]:
			total += int(unit["count"])
	return total


func _draw_header_button(font: Font, rect: Rect2, icon: String, caption: String) -> void:
	draw_rect(rect, Color("303833"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), PALETTE["panel_edge"])
	draw_string(
		font,
		Vector2(rect.position.x, rect.position.y + 24),
		icon,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		17,
		PALETTE["paper"]
	)
	draw_string(
		font,
		Vector2(rect.position.x, rect.position.y + 43),
		caption,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		9,
		PALETTE["muted"]
	)


func _draw_bottom_hud(font: Font) -> void:
	draw_rect(Rect2(0, 580, 1280, 140), Color("202723"))
	draw_rect(Rect2(0, 580, 1280, 2), Color("9b8758"))
	for i in range(4):
		_draw_unit_card(font, i)
	var labels := ["ATTACK", "HOLD", "CHARGE", "FIRE AT WILL"]
	var actions := ["attack", "hold", "charge", "fire"]
	var xs := [662.0, 806.0, 950.0, 1094.0]
	for i in range(4):
		var unit := _get_selected()
		var active := not unit.is_empty() and unit["order"] == actions[i]
		_draw_action_button(font, Rect2(xs[i], 590, 132, 50), labels[i], active, i)
	_draw_action_button(font, Rect2(662, 648, 132, 50), "RALLY", false, 4)
	var selected := _get_selected()
	if not selected.is_empty():
		var cls := str(selected["role"]).to_upper()
		draw_string(
			font,
			Vector2(820, 670),
			"SELECTED: " + cls + "     •     AIM FOR MORALE BREAK",
			HORIZONTAL_ALIGNMENT_LEFT,
			400,
			11,
			PALETTE["muted"]
		)
	draw_string(
		font, Vector2(18, 578), "YOUR REGIMENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, PALETTE["gold"]
	)


func _draw_unit_card(font: Font, index: int) -> void:
	var unit: Dictionary = units[index]
	var rect := Rect2(18 + index * 151, 590, 143, 110)
	var selected := unit["id"] == selected_id
	var card_color := Color("343d37") if selected else Color("292f2b")
	draw_rect(rect, card_color)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 3)),
		Color("d0b779") if selected else Color("5d6658")
	)
	var swatch := Color(str(unit["color"]))
	draw_rect(Rect2(rect.position + Vector2(9, 12), Vector2(17, 17)), swatch)
	draw_rect(Rect2(rect.position + Vector2(13, 16), Vector2(9, 9)), Color(str(unit["accent"])))
	var title := str(unit["name"])
	draw_string(
		font,
		rect.position + Vector2(33, 25),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		105,
		11,
		PALETTE["paper"]
	)
	draw_string(
		font,
		rect.position + Vector2(10, 48),
		str(unit["count"]) + " soldiers",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		PALETTE["white"] if unit["alive"] else PALETTE["red"]
	)
	draw_string(
		font,
		rect.position + Vector2(10, 65),
		str(unit["order"]).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		PALETTE["gold"]
	)
	draw_rect(Rect2(rect.position + Vector2(10, 76), Vector2(120, 6)), Color("171d1a"))
	draw_rect(
		Rect2(
			rect.position + Vector2(10, 76), Vector2(120.0 * float(unit["morale_now"]) / 100.0, 6)
		),
		PALETTE["morale"] if float(unit["morale_now"]) > 17.0 else PALETTE["red"]
	)
	draw_string(
		font,
		rect.position + Vector2(10, 99),
		"MORALE  " + str(int(unit["morale_now"])) + "%",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		PALETTE["muted"]
	)
	if int(unit["range"]) > 0:
		draw_string(
			font,
			rect.position + Vector2(93, 99),
			"ARW " + str(unit["ammo"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			9,
			PALETTE["muted"]
		)
	if not unit["alive"]:
		draw_rect(rect, Color(0.10, 0.10, 0.10, 0.58))
		draw_string(
			font,
			rect.position + Vector2(40, 58),
			"ROUTED",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			PALETTE["red"]
		)


func _draw_action_button(
	font: Font, rect: Rect2, label: String, active: bool, icon_index: int
) -> void:
	var bg := Color("60553c") if active else Color("303833")
	draw_rect(rect, bg)
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, 2)),
		PALETTE["gold"] if active else PALETTE["panel_edge"]
	)
	var icon := ["⚔", "▤", "➤", "↗", "+"][icon_index]
	draw_string(
		font,
		rect.position + Vector2(8, 32),
		icon,
		HORIZONTAL_ALIGNMENT_LEFT,
		26,
		17,
		PALETTE["gold"]
	)
	draw_string(
		font,
		rect.position + Vector2(34, 31),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 39,
		11,
		PALETTE["paper"]
	)


func _draw_feedback(font: Font) -> void:
	if message_timer > 0.0:
		var width := minf(680.0, maxf(330.0, float(help_message.length()) * 8.0))
		var rect := Rect2((1280.0 - width) * 0.5, 88, width, 34)
		draw_rect(rect, Color(0.12, 0.15, 0.13, 0.90))
		draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), PALETTE["gold"])
		draw_string(
			font,
			rect.position + Vector2(15, 22),
			help_message,
			HORIZONTAL_ALIGNMENT_LEFT,
			width - 25,
			12,
			PALETTE["paper"]
		)
	var minutes := int(battle_time) / 60
	var seconds := int(battle_time) % 60
	draw_string(
		font,
		Vector2(1190, 560),
		"%02d:%02d" % [minutes, seconds],
		HORIZONTAL_ALIGNMENT_RIGHT,
		65,
		12,
		PALETTE["paper"]
	)


func _draw_pause_overlay(font: Font) -> void:
	draw_rect(FIELD, Color(0.06, 0.08, 0.07, 0.54))
	draw_rect(Rect2(495, 244, 290, 102), Color("252c29"))
	draw_rect(Rect2(495, 244, 290, 3), PALETTE["gold"])
	draw_string(
		font,
		Vector2(495, 285),
		"BATTLE PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER,
		290,
		20,
		PALETTE["paper"]
	)
	draw_string(
		font,
		Vector2(495, 318),
		"Tap the pause button to resume",
		HORIZONTAL_ALIGNMENT_CENTER,
		290,
		12,
		PALETTE["muted"]
	)


func _draw_result_overlay(font: Font) -> void:
	draw_rect(FIELD, Color(0.05, 0.07, 0.06, 0.72))
	draw_rect(Rect2(358, 245, 564, 260), Color("252c29"))
	draw_rect(Rect2(358, 245, 564, 4), PALETTE["gold"] if victory else PALETTE["red"])
	draw_string(
		font,
		Vector2(358, 303),
		"THE FIELD IS DECIDED",
		HORIZONTAL_ALIGNMENT_CENTER,
		564,
		13,
		PALETTE["gold"]
	)
	draw_string(
		font,
		Vector2(378, 355),
		battle_result,
		HORIZONTAL_ALIGNMENT_CENTER,
		524,
		21,
		PALETTE["paper"]
	)
	draw_string(
		font,
		Vector2(378, 389),
		"A battle record was written to your autosave.",
		HORIZONTAL_ALIGNMENT_CENTER,
		524,
		12,
		PALETTE["muted"]
	)
	draw_rect(Rect2(490, 415, 300, 70), Color("5a533d"))
	draw_rect(Rect2(490, 415, 300, 3), PALETTE["gold"])
	draw_string(
		font,
		Vector2(490, 458),
		"FIGHT AGAIN",
		HORIZONTAL_ALIGNMENT_CENTER,
		300,
		16,
		PALETTE["paper"]
	)
