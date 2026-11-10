extends SceneTree


# Lightweight headless checks for the data assumptions used by Phase 1.
func _initialize() -> void:
	var content := FileAccess.get_file_as_string("res://data/units.json")
	var parsed: Variant = JSON.parse_string(content)
	assert(parsed is Dictionary)
	assert(parsed.has("units"))
	var templates: Array = parsed["units"]
	assert(templates.size() == 8)
	var team_totals := [0, 0]
	for index in range(templates.size()):
		var unit: Dictionary = templates[index]
		assert(int(unit["count"]) > 0)
		assert(int(unit["attack"]) > 0)
		assert(int(unit["armor"]) >= 0)
		assert(int(unit["morale"]) in range(0, 101))
		if int(unit["range"]) > 0:
			assert(int(unit["ammo"]) > 0)
		team_totals[0 if index < 4 else 1] += int(unit["count"])
	assert(team_totals[0] > 0 and team_totals[1] > 0)
	print("Phase 1 unit-data smoke test passed: ", team_totals)
	quit()
