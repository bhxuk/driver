extends SceneTree
## Dev helper: runs the game plus a probe script. Usage:
##   PROBE=drive_probe godot --headless --path . -s tools/probe_scene.gd -- --solo --map=desert
func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var p = load("res://tools/%s.gd" % OS.get_environment("PROBE")).new()
	root.add_child(p)
