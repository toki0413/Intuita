shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// 守恒场辉光 - 根据特征值偏离程度变色
// 绿色(健康) -> 黄色(警告) -> 红色(危险)
// 含能量场流动线条效果

uniform float deviation : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.5, 5.0) = 2.0;
uniform float intensity : hint_range(0.1, 3.0) = 1.0;
uniform float eigenvalue_magnitude : hint_range(0.0, 2.0) = 1.0;
uniform vec3 healthy_color : source_color = vec3(0.1, 0.9, 0.3);
uniform vec3 warning_color : source_color = vec3(0.9, 0.85, 0.1);
uniform vec3 critical_color : source_color = vec3(0.95, 0.15, 0.05);

varying vec3 v_position;
varying vec3 v_world_pos;
varying vec3 v_normal;


// 简单2D噪声
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
	v_position = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = NORMAL;
}


void fragment() {
	// 根据偏离度插值颜色（使用uniform，支持色盲模式）
	vec3 base_color;
	float local_pulse_speed = pulse_speed;

	if (deviation < 0.3) {
		base_color = mix(healthy_color, warning_color, deviation / 0.3);
		local_pulse_speed = pulse_speed * 0.8;
	} else if (deviation < 0.7) {
		base_color = mix(warning_color, critical_color, (deviation - 0.3) / 0.4);
		local_pulse_speed = pulse_speed * 1.5;
	} else {
		base_color = critical_color;
		local_pulse_speed = pulse_speed * 3.0;
	}

	float pulse = 0.5 + 0.5 * sin(TIME * local_pulse_speed);

	// 绿色脉动强度与特征值关联
	float eigen_factor = 0.5 + 0.5 * eigenvalue_magnitude;
	float alpha = (0.3 + 0.4 * pulse) * intensity * eigen_factor;

	// 黄色警告: 轻微扭曲
	if (deviation >= 0.3 && deviation < 0.7) {
		float distort = sin(v_position.y * 10.0 + TIME * 3.0) * 0.02 * deviation;
		alpha += distort;
	}

	// 红色危险: 几何扭曲波
	if (deviation >= 0.7) {
		float wave = sin(v_position.y * 20.0 - TIME * 8.0) * 0.5 + 0.5;
		wave = pow(wave, 3.0);
		alpha += wave * 0.3 * (deviation - 0.7) / 0.3;
		// 闪烁效果
		float flash = step(0.5, sin(TIME * 8.0));
		alpha = mix(alpha, alpha * 2.0, flash * 0.3);
	}

	// 边缘辉光
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	rim = pow(rim, 2.0);
	alpha *= (0.5 + 0.5 * rim);

	// 能量场流动线条 - 沿表面流动的细线
	vec2 flow_uv = v_world_pos.xy * 3.0;
	float flow_noise = noise2d(flow_uv + vec2(0.0, -TIME * 0.5));
	float flow_line = smoothstep(0.4, 0.5, flow_noise) * smoothstep(0.6, 0.5, flow_noise);
	flow_line *= 0.3 * intensity;

	// 第二层流动 - 不同方向
	float flow_noise2 = noise2d(v_world_pos.yz * 4.0 + vec2(TIME * 0.3, 0.0));
	float flow_line2 = smoothstep(0.42, 0.5, flow_noise2) * smoothstep(0.58, 0.5, flow_noise2);
	flow_line2 *= 0.2 * intensity;

	// 能量场颜色与偏离度一致
	vec3 flow_color = base_color * 1.5;

	ALBEDO = base_color * (1.0 + rim * 0.5) + flow_color * (flow_line + flow_line2);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
