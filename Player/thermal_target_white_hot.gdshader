shader_type canvas_item;
render_mode unshaded;

uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 hot_color : source_color = vec4(1.0, 0.99, 0.84, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 0.96, 1.0);
uniform vec4 edge_color : source_color = vec4(0.52, 0.92, 0.64, 1.0);
uniform float edge_power : hint_range(0.5, 4.0) = 1.6;

void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float alpha = source.a;
	float heat_mask = smoothstep(0.02, 0.20, alpha);
	float core_mask = pow(heat_mask, edge_power);
	vec3 heat_color = mix(edge_color.rgb, hot_color.rgb, heat_mask);
	heat_color = mix(heat_color, core_color.rgb, core_mask);
	vec3 result = mix(source.rgb, heat_color, intensity);
	COLOR = vec4(result, alpha);
}
