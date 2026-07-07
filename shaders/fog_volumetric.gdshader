shader_type fog;

// 体积迷雾 - 三种变体对应三种迷雾类型
// 0: SEMI_DECIDABLE (淡紫薄雾, 脉动密度, 缓慢上升粒子)
// 1: UNDECIDABLE (深紫浓雾, 静态密度, 压迫感)
// 2: INDEPENDENT (暗紫黑漩涡, 旋转, 暗色触须, 数学符号)

uniform int fog_type : hint_range(0, 2) = 0;
uniform float density : hint_range(0.1, 2.0) = 0.8;
uniform float noise_scale : hint_range(0.5, 10.0) = 3.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float peek_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float ripple_strength : hint_range(0.0, 3.0) = 0.0;
uniform float symbol_glow : hint_range(0.0, 1.0) = 0.0;


// 3D哈希
float hash(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

// 3D值噪声
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec3(1, 0, 0));
	float c = hash(i + vec3(0, 1, 0));
	float d = hash(i + vec3(1, 1, 0));
	float e = hash(i + vec3(0, 0, 1));
	float ff = hash(i + vec3(1, 0, 1));
	float g = hash(i + vec3(0, 1, 1));
	float h = hash(i + vec3(1, 1, 1));

	return mix(
		mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
		mix(mix(e, ff, f.x), mix(g, h, f.x), f.y),
		f.z
	);
}

// 分形噪声 (FBM)
float fbm(vec3 p, int octaves) {
	float val = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		val += amp * noise3d(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return val;
}

// 旋转矩阵 (2D)
vec2 rotate2d(vec2 v, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}


void fog() {
	// 三种迷雾颜色
	vec3 semi_color = vec3(0.3, 0.5, 1.0);       // 蓝色 - 半可判定
	vec3 undec_color = vec3(0.5, 0.1, 0.7);       // 深紫 - 不可判定
	vec3 indep_color = vec3(0.05, 0.0, 0.08);     // 近纯黑 - 独立

	// 基础密度
	float base_density = 0.0;
	vec3 fog_color = semi_color;
	float n = 0.0;

	if (fog_type == 0) {
		// === 半可判定: 蓝色薄雾, 脉动, 缓慢上升 ===
		float pulse = 0.5 + 0.5 * sin(TIME * 1.5708);
		vec3 scroll = vec3(0.0, TIME * 0.15, 0.0);
		n = fbm(WORLD_POSITION * noise_scale + scroll, 3);
		n = smoothstep(0.2, 0.8, n);

		float pulsing_density = density * (0.7 + 0.3 * pulse);
		base_density = n * pulsing_density * 0.15;
		fog_color = semi_color * (1.0 + 0.1 * pulse);

		// 涟漪效果 - 调查时粒子汇聚
		if (ripple_strength > 0.0) {
			float ripple = sin(length(OBJECT_POSITION.xz) * 8.0 - TIME * 4.0) * 0.5 + 0.5;
			base_density *= 1.0 + ripple * ripple_strength * 0.3;
		}

	} else if (fog_type == 1) {
		// === 不可判定: 深紫浓雾, 静态, 压迫感 ===
		n = fbm(WORLD_POSITION * noise_scale * 1.3, 4);
		n = smoothstep(0.1, 0.5, n);

		base_density = n * density * 0.4;
		fog_color = undec_color * (1.0 + n * 0.2);

		// 闪电效果 - 穿透失败时
		if (ripple_strength > 0.0) {
			float lightning = pow(sin(TIME * 30.0) * 0.5 + 0.5, 8.0);
			fog_color += vec3(0.6, 0.2, 1.0) * lightning * ripple_strength * 0.5;
			base_density *= 1.0 + ripple_strength * 0.2;
		}

	} else {
		// === 独立: 近纯黑漩涡, 旋转, 数学符号 ===
		vec3 p = WORLD_POSITION * noise_scale;
		float angle = TIME * 0.8;
		vec2 swirl = rotate2d(p.xz, angle + length(p.xz) * 0.5);
		p.xz = swirl;

		n = fbm(p, 4);
		float tendril = sin(atan(OBJECT_POSITION.z, OBJECT_POSITION.x) * 5.0 + TIME * 1.2) * 0.5 + 0.5;
		tendril = pow(tendril, 2.0);
		n = mix(n, n * 0.3, tendril * 0.6);

		base_density = n * density * 0.6;
		fog_color = indep_color * (1.0 + tendril * 0.3);

		// 数学符号滚动效果 - 用周期性条纹模拟
		float symbol_phase = fract(WORLD_POSITION.y * 2.0 + TIME * 0.3);
		float symbol_line = smoothstep(0.45, 0.5, symbol_phase) * smoothstep(0.55, 0.5, symbol_phase);
		float symbol_x = sin(WORLD_POSITION.x * 15.0 + TIME * 0.5) * 0.5 + 0.5;
		symbol_x = step(0.7, symbol_x);
		float symbol_pattern = symbol_line * symbol_x;
		fog_color += vec3(0.15, 0.0, 0.05) * symbol_pattern * 0.4;

		// 交互时符号发红光
		if (symbol_glow > 0.0) {
			fog_color += vec3(0.8, 0.0, 0.0) * symbol_pattern * symbol_glow;
		}
	}

	// 距离衰减 - 中心浓边缘淡 (UVW: 0-1 within volume AABB)
	float dist_from_center = length(UVW - 0.5);
	float dist_fade = 1.0 - smoothstep(0.25, 0.5, dist_from_center);

	base_density *= dist_fade;

	// 应用全局淡入淡出
	base_density *= fade;

	// 窥视效果 - 降低密度
	base_density *= 1.0 - peek_opacity * 0.7;

	ALBEDO = fog_color * (1.0 + n * 0.3);
	DENSITY = clamp(base_density, 0.0, 0.95);
}
