# Block C manual validation

1. Open `res://tests/manual_block_c_validation.tscn` in the Godot editor.
2. Select `ManualBlockCValidation`; set `world_seed` in the Inspector.
3. Press **Generate Block C preview**. It clears the previous preview, rasterizes real `RoadTileSet` tiles, then instantiates the approved `Village.tscn` POI content.
4. Toggle `show_poi_bounds`, `show_connector`, `show_road`, `show_road_clearance`, and `show_generated_object_ids` in the Inspector.
5. Capture editor screenshots for seeds `1337`, `7331`, and `15885`. For each, verify one green POI bounds rectangle, magenta connector/facing, no overlap with blue clearance, and generated houses, ruins, and small objects at zero Village rotation.
6. Use **Clear Block C preview** before changing a seed or closing the scene.
