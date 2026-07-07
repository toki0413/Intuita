shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// 金色护盾 - L5 (Z3形式化约束验证) 通过的节点
// 金色辉光 + 六角网格纹理 + 上升光效 + 闪烁粒子 + 光晕

uniform float glow_intensity : hint_range(0.5, 3.0) = 1.5;
uniform float pulse_speed : hint_range(0.5, 4.0) = 1.5;
uniform float hex_scale : hint_range(2.0, 20.0) = 8.0;
uniform float activation_time : hint_range(0.0, 10.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec2 v_uv;


// 六角网格距离
float hex_dist(vec2 p) {
	p = abs(p);
	float c = dot(p, normalize(vec2(1.0, 1.73)));
	float d = dot(p, normalize(vec2(1.0, -1.73)));
	return max(c, d);
}

vec4 hex_coords(vec2 uv) {
	vec2 r = vec2(1.0, 1.73);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv + h, r) - h;
	vec2 gv = dot(a, a) < dot(b, b) ? a : b;

	float x = atan(gv.x, gv.y);
	float y = 0.5 - hex_dist(gv);
	vec2 id = uv - gv;
	return vec4(x, y, id.x, id.y);
}

// 伪随机
float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D噪声
float hash2d(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2d(i);
	float b = hash2d(i + vec2(1.0, 0.0));
	float c = hash2d(i + vec2(0.0, 1.0));
	float d = hash2d(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_pos = VERTEX;
	v_uv = UV;
}


void fragment() {
	// 激活阶段: 强脉冲 → 稳定暖光
	float age = TIME - activation_time;
	float activation_pulse = 1.0;
	if (age < 2.0) {
		// 前2秒: 强烈脉冲
		activation_pulse = 1.0 + 1.5 * exp(-age * 2.0) * sin(age * 10.0);
		activation_pulse = max(activation_pulse, 0.3);
	}

	float steady_pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	float pulse = mix(steady_pulse, activation_pulse, step(age, 2.0));

	// 六角网格
	vec2 scaled_uv = v_world_pos.xz * hex_scale * 0.1;
	vec4 hc = hex_coords(scaled_uv);
	float hex_line = smoothstep(0.0, 0.05, hc.y);

	// 金色基底
	vec3 gold_base = vec3(0.85, 0.65, 0.1);
	vec3 gold_bright = vec3(1.0, 0.85, 0.3);

	vec3 color = mix(gold_bright, gold_base, hex_line);

	// 上升光效 - 光从底部向上流动
	float rise_phase = fract(v_local_pos.y * 0.8 - TIME * 0.3);
	float rising_light = smoothstep(0.0, 0.3, rise_phase) * smoothstep(0.6, 0.3, rise_phase);
	rising_light *= 0.4;
	color += gold_bright * rising_light;

	// 闪烁粒子 - 在表面随机位置产生亮点
	vec2 sparkle_uv = v_world_pos.xz * 20.0;
	float sparkle_noise = noise2d(sparkle_uv + vec2(TIME * 2.0, TIME * 1.5));
	float sparkle = pow(max(sparkle_noise - 0.7, 0.0) / 0.3, 3.0);
	sparkle *= 2.0;
	color += vec3(1.0, 0.95, 0.8) * sparkle;

	// 边缘辉光
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	rim = pow(rim, 2.0);

	color += gold_bright * rim * 0.8;

	// 脉动
	color *= (0.8 + 0.2 * pulse);

	float alpha = (0.4 + 0.3 * pulse) * glow_intensity;
	alpha *= (0.5 + 0.5 * rim);

	// 光晕效果 - 在物体周围形成柔和的发光圈
	float halo = pow(rim, 0.5) * 0.15 * glow_intensity;
	color += gold_bright * halo;
	alpha += halo;

	ALBEDO = color;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
