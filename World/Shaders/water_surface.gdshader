shader_type canvas_item;

uniform vec4 cold_tint : source_color = vec4(0.58, 0.82, 0.94, 1.0);
uniform vec4 glint_color : source_color = vec4(0.78, 0.94, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 0.5) = 0.10;
uniform float glint_strength : hint_range(0.0, 0.5) = 0.12;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.55;
uniform float wave_scale : hint_range(0.005, 0.2) = 0.035;
uniform float pixel_step : hint_range(1.0, 16.0, 1.0) = 4.0;

varying vec2 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	vec2 pixel_world = floor(world_position / pixel_step) * pixel_step;
	float animation_time = TIME * wave_speed;
	float long_wave = sin((pixel_world.x + pixel_world.y * 0.42) * wave_scale + animation_time);
	float cross_wave = sin((pixel_world.x * -0.31 + pixel_world.y) * wave_scale * 1.7 - animation_time * 0.73);
	float wave = long_wave * 0.68 + cross_wave * 0.32;
	float glint = smoothstep(0.72, 0.96, wave * 0.5 + 0.5);

	vec3 tinted = source.rgb * cold_tint.rgb;
	source.rgb = mix(source.rgb, tinted, tint_strength);
	source.rgb += glint_color.rgb * glint * glint_strength * source.a;
	COLOR = source;
}
