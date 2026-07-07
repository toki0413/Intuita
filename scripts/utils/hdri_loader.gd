class_name HDRILoader extends Node

## 静态工具：将 HDRI 纹理加载到 Environment 中
## 失败时返回 false，调用方应保留原有 Sky（如 ProceduralSky）作为回退

static func load_hdri_into_environment(env: Environment, hdri_path: String) -> bool:
	if not ResourceLoader.exists(hdri_path):
		return false

	var panorama := PanoramaSkyMaterial.new()
	var texture := load(hdri_path) as Texture2D
	if texture == null:
		return false

	panorama.panorama = texture
	panorama.filter = true

	var sky := Sky.new()
	sky.sky_material = panorama

	env.sky = sky
	env.background_mode = Environment.BG_SKY
	return true
