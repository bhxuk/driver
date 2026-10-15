# Custom models

Driver generates simple low-poly models for everything, so it works with no art at all. To use real models (for example the free [Quaternius](https://quaternius.com) packs), drop files into the folders below and rebuild or press Play in Godot. Supported formats: `.glb`, `.gltf`, `.tscn`, `.obj`.

| Folder | Used for | Fitted height |
| --- | --- | --- |
| `assets/props/pine/` | Forest conifers | 9 m |
| `assets/props/broadleaf/` | Forest leafy trees | 7 m |
| `assets/props/bush/` | Forest bushes | 1.5 m |
| `assets/props/pine_snow/` | Snowy conifers | 9 m |
| `assets/props/rock/` | Small and medium rocks (all maps) | scaled per rock |
| `assets/props/boulder/` | Big rocks (desert, snow) | scaled per rock |
| `assets/props/cactus/` | Desert cacti | 4.5 m |
| `assets/props/dead_tree/` | Desert dead trees | 5 m |
| `assets/vehicles/truck/` | The truck body (first file found) | 4.6 m long |

Notes

- Put several models in one folder to get variety. Each tree, rock and so on picks one at random, the same on every player's PC.
- Models are scaled so their height matches the table and their base sits on the ground. Rotation is randomised.
- For the truck, the model should face **-Z** (Godot's forward). The generated wheels, lights and cargo stay, so a body without wheels works best.
- Collision stays simple (a cylinder for trees, a sphere for rocks), so physics behaves the same whatever the model looks like.
- Everyone in a co-op session should run the same build so the worlds match.

Good Quaternius packs to start with: **Ultimate Nature Pack** or **Stylized Nature MegaKit** (trees, rocks, bushes) and **Cars** or **Ultimate Vehicles** (pickup trucks).
