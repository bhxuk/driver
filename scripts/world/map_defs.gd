class_name MapDefs
extends RefCounted
## Static descriptions of every map. Terrain is generated from these on every peer
## with the same seed, so nothing about the world itself needs sending over the network.

const IDS := ["forest", "desert", "snow"]


static func get_def(id: String) -> Dictionary:
	match id:
		"desert":
			return {
				"id": "desert",
				"name": "Red Canyon",
				"tagline": "Dunes, mesas and dry riverbeds under a hard sun.",
				"seed": 7342,
				"kind": "canyon",
				"hub": Vector2(-180, 260),
				"water_level": -1000.0,
				"base_surface_name": "Sand",
				"special_surface_name": "Soft sand",
				"colors": {
					"base": Color("d49a5a"), "base2": Color("c4824a"), "rock": Color("9c4f35"),
					"rock2": Color("7d3d2a"), "road": Color("e3c08c"), "special": Color("e8b878"),
					"high": Color("b5643f"), "water": Color("3e6f80"),
				},
				"grip": {"base": 0.68, "road": 1.0, "special": 0.45, "rock": 0.95, "water": 0.5},
				"drag": {"base": 0.15, "road": 0.0, "special": 0.9, "rock": 0.0, "water": 2.0},
				"sky_top": Color("4f86c6"), "sky_horizon": Color("e9c79c"), "ground_horizon": Color("b98454"),
				"fog_color": Color("e2b98a"), "fog_density": 0.0009,
				"sun_color": Color("fff0d6"), "sun_energy": 1.35, "sun_pitch": -52.0, "sun_yaw": 35.0,
				"ambient_energy": 0.7,
				"weather": "dust",
				"props": [
					{"type": "cactus", "count": 420, "max_slope": 0.45},
					{"type": "dead_tree", "count": 140, "max_slope": 0.4},
					{"type": "rock", "count": 520, "max_slope": 1.4},
					{"type": "boulder", "count": 120, "max_slope": 1.2},
				],
			}
		"snow":
			return {
				"id": "snow",
				"name": "Frostline Peak",
				"tagline": "Switchbacks, ice sheets and a summit worth the climb.",
				"seed": 1911,
				"kind": "mountain",
				"hub": Vector2(-330, 300),
				"water_level": -1000.0,
				"base_surface_name": "Snow",
				"special_surface_name": "Ice",
				"colors": {
					"base": Color("eef3f7"), "base2": Color("d8e2ea"), "rock": Color("6e747c"),
					"rock2": Color("585d64"), "road": Color("b8a993"), "special": Color("a9d4ea"),
					"high": Color("ffffff"), "water": Color("4c7a91"),
				},
				"grip": {"base": 0.62, "road": 0.92, "special": 0.2, "rock": 0.85, "water": 0.5},
				"drag": {"base": 0.35, "road": 0.0, "special": 0.0, "rock": 0.0, "water": 2.0},
				"sky_top": Color("6d8fb5"), "sky_horizon": Color("d6e2ec"), "ground_horizon": Color("c7d3dd"),
				"fog_color": Color("dfe8ef"), "fog_density": 0.0016,
				"sun_color": Color("f4f6ff"), "sun_energy": 1.05, "sun_pitch": -32.0, "sun_yaw": -40.0,
				"ambient_energy": 0.85,
				"weather": "snow",
				"props": [
					{"type": "pine_snow", "count": 1100, "max_slope": 0.6, "max_height": 95.0},
					{"type": "rock", "count": 380, "max_slope": 1.5},
					{"type": "boulder", "count": 70, "max_slope": 1.2},
				],
			}
		_:
			return {
				"id": "forest",
				"name": "Green Hollow",
				"tagline": "Muddy tracks, a river crossing and thick woodland.",
				"seed": 4021,
				"kind": "hills",
				"hub": Vector2(-260, -250),
				"water_level": 0.0,
				"base_surface_name": "Grass",
				"special_surface_name": "Mud",
				"colors": {
					"base": Color("6f9a45"), "base2": Color("5b8638"), "rock": Color("7b7a72"),
					"rock2": Color("66655e"), "road": Color("9b7b52"), "special": Color("5a4130"),
					"high": Color("86a856"), "water": Color("3d6f78"),
				},
				"grip": {"base": 0.8, "road": 1.0, "special": 0.42, "rock": 0.9, "water": 0.55},
				"drag": {"base": 0.05, "road": 0.0, "special": 1.2, "rock": 0.0, "water": 2.5},
				"sky_top": Color("5d8fc9"), "sky_horizon": Color("c9dbe6"), "ground_horizon": Color("8aa070"),
				"fog_color": Color("bfd0d6"), "fog_density": 0.0011,
				"sun_color": Color("fff4e0"), "sun_energy": 1.2, "sun_pitch": -45.0, "sun_yaw": 140.0,
				"ambient_energy": 0.75,
				"weather": "none",
				"props": [
					{"type": "pine", "count": 900, "max_slope": 0.7},
					{"type": "broadleaf", "count": 650, "max_slope": 0.55},
					{"type": "bush", "count": 500, "max_slope": 0.7},
					{"type": "rock", "count": 260, "max_slope": 1.4},
				],
			}


static func display_name(id: String) -> String:
	return str(get_def(id)["name"])
