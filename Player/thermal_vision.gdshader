shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float time_sec = 0.0;
uniform float pixel_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float contrast : hint_range(0.5, 3.0) = 1.08;
uniform float brightness_bias : hint_range(-0.5, 0.5) = 0.10;
uniform float noise_amount : hint_range(0.0, 0.3) = 0.014;
uniform float scanline_strength : hint_range(0.0, 0.6) = 0.030;
uniform float jitter_strength : hint_range(0.0, 0.01) = 0.00055;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.08;
uniform float cold_visibility : hint_range(0.0, 1.0) = 0.58;
uniform float white_hot_threshold : hint_range(0.70, 1.0) = 0.88;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 thermal_palette(float heat) {
	heat = clamp(heat, 0.0, 1.0);

	vec3 black_green = vec3(0.035, 0.070, 0.050);
	vec3 murk_green = vec3(0.075, 0.165, 0.105);
	vec3 phosphor = vec3(0.230, 0.520, 0.285);
	vec3 pale_green = vec3(0.620, 0.850, 0.610);
	vec3 hot_white = vec3(1.000, 0.985, 0.820);

	if (heat < 0.34) {
		return mix(black_green, murk_green, heat / 0.34);
	}
	if (heat < 0.66) {
		return mix(murk_green, phosphor, (heat - 0.34) / 0.32);
	}
	if (heat < 0.88) {
		return mix(phosphor, pale_green, (heat - 0.66) / 0.22);
	}
	return mix(pale_green, hot_white, (heat - 0.88) / 0.12);
}

void fragment() {
	vec2 viewport_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	float row_noise = hash21(vec2(floor(uv.y * viewport_size.y * 0.35), floor(time_sec * 18.0)));
	float wave = sin((uv.y * 420.0) + (time_sec * 13.0)) * jitter_strength;
	uv.x += wave + ((row_noise - 0.5) * jitter_strength * 1.4);

	vec2 pixelated_uv = floor(uv * viewport_size / pixel_size) * pixel_size / viewport_size;
	vec4 source = texture(screen_texture, pixelated_uv);

	float luma = dot(source.rgb, vec3(0.299, 0.587, 0.114));
	float heat = pow(clamp((luma + brightness_bias) * contrast, 0.0, 1.0), 0.90);

	float grain = hash21(floor(pixelated_uv * viewport_size / max(pixel_size, 1.0)) + vec2(time_sec * 37.0, time_sec * 11.0));
	heat = clamp(heat + ((grain - 0.5) * noise_amount), 0.0, 1.0);

	float white_hot = smoothstep(white_hot_threshold, 1.0, heat);
	vec3 cold_detail = vec3(luma) * vec3(0.10, 0.22, 0.13) * cold_visibility;
	vec3 thermal = max(thermal_palette(heat), cold_detail);
	thermal = mix(thermal, vec3(1.0, 0.99, 0.86), white_hot);

	float scanline = 1.0 - (sin((SCREEN_UV.y * viewport_size.y * 3.14159) + time_sec * 18.0) * 0.5 + 0.5) * scanline_strength;
	float vignette = smoothstep(0.92, 0.30, distance(SCREEN_UV, vec2(0.5))) * (1.0 - vignette_strength) + vignette_strength;
	thermal *= scanline * vignette;

	vec3 result = mix(source.rgb, thermal, intensity);
	COLOR = vec4(result, 1.0);
}
