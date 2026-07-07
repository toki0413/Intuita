shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// 瓦解粒子着色器 - 守恒矩阵崩溃时的视觉效果
// Voronoi裂纹扩展 + 碎片旋转飞散 + 热扭曲 + 颜色过渡

uniform float disintegration_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 base_color : source_color = vec3(0.6, 0.0, 0.8);
uniform float particle_size : hint_range(0.01, 0.5) = 0.1;
uniform float scatter_strength : hint_range(0.0, 5.0) = 2.0;
uniform vec3 crack_origin : source_color = vec3(0.0, 0.0, 0.0);

varying vec3 v_offset;
varying float v_life;
varying vec3 v_local_pos;
varying float v_crack_dist;


// 伪随机
float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// 2D哈希
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// Voronoi距离 - 用于裂纹图案
float voronoi(vec2 uv) {
	vec2 g = floor(uv);
	vec2 f = fract(uv);
	float min_dist = 1.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(g + neighbor);
			// 让Voronoi点随进度动画化 - 裂纹扩展
			point = 0.5 + 0.5 * sin(TIME * 0.5 + 6.2831 * point);
			float d = length(neighbor + point - f);
			min_dist = min(min_dist, d);
		}
	}
	return min_dist;
}


void vertex() {
	v_local_pos = VERTEX;

	// 每个顶点基于UV获得随机偏移
	vec2 seed = UV * 100.0;
	float r1 = rand(seed);
	float r2 = rand(seed + 0.5);
	float r3 = rand(seed + 0.25);

	v_offset = vec3(r1 - 0.5, r2 - 0.5, r3 - 0.5) * scatter_strength;
	v_life = r1;

	// 裂纹距离 - 从crack_origin扩展
	float dist_to_origin = distance(v_local_pos, crack_origin);
	v_crack_dist = dist_to_origin;

	// 裂纹到达时间 (距离越近越早开裂)
	float crack_arrival = dist_to_origin * 1.5;

	// 随着瓦解进度，顶点向外飞散
	float progress = disintegration_progress * (0.5 + v_life * 0.5);
	vec3 scattered = VERTEX + v_offset * progress;

	// 碎片旋转 - 每个碎片绕自身轴旋转
	float angle = progress * 6.2831 * v_life;
	float rot_speed = 1.0 + v_life * 2.0;
	angle *= rot_speed;
	mat2 rot = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	scattered.xz = rot * scattered.xz;

	// Y轴也加一点旋转
	float angle_y = progress * 3.14159 * v_life * 0.5;
	mat2 rot_y = mat2(vec2(cos(angle_y), -sin(angle_y)), vec2(sin(angle_y), cos(angle_y)));
	scattered.xy = rot_y * scattered.xy;

	VERTEX = mix(VERTEX, scattered, progress);

	// 缩小
	float scale = 1.0 - progress * 0.8;
	VERTEX *= max(scale, 0.01);
}


void fragment() {
	float progress = disintegration_progress * (0.5 + v_life * 0.5);

	// Voronoi裂纹
	vec2 voronoi_uv = v_local_pos.xz * 8.0;
	float v = voronoi(voronoi_uv);

	// 裂纹线 - Voronoi边缘
	float crack_line = 1.0 - smoothstep(0.0, 0.08, v);
	// 裂纹从origin向外扩展
	float crack_reach = disintegration_progress * 3.0;
	float crack_mask = smoothstep(crack_reach, crack_reach - 0.5, v_crack_dist);
	crack_line *= crack_mask;

	// 热扭曲效果 - 裂纹边缘附近
	float heat_zone = smoothstep(0.15, 0.0, v) * crack_mask;
	float heat_distort = sin(v_local_pos.y * 30.0 + TIME * 10.0) * heat_zone * 0.05 * disintegration_progress;

	// 颜色过渡: 基色 → 橙色 → 红色 → 黑色
	vec3 orange = vec3(1.0, 0.5, 0.0);
	vec3 red = vec3(0.9, 0.1, 0.0);
	vec3 black = vec3(0.05, 0.0, 0.0);

	vec3 color;
	if (progress < 0.3) {
		color = mix(base_color, orange, progress / 0.3);
	} else if (progress < 0.6) {
		color = mix(orange, red, (progress - 0.3) / 0.3);
	} else {
		color = mix(red, black, (progress - 0.6) / 0.4);
	}

	// 裂纹线发光 - 橙白色
	vec3 crack_glow = mix(vec3(1.0, 0.8, 0.3), vec3(1.0, 1.0, 0.9), crack_line);
	color = mix(color, crack_glow, crack_line * 0.8);

	// 热扭曲影响颜色
	color += vec3(0.3, 0.1, 0.0) * heat_zone * disintegration_progress;

	// 透明度随进度降低
	float alpha = 1.0 - progress;
	alpha = max(alpha, 0.0);

	// 边缘发光
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	alpha *= (0.6 + 0.4 * rim);

	ALBEDO = color;
	ALPHA = alpha;
}
