class_name MatrixMath

# Accept untyped Array — callers (e.g. ConservationEngine.matrix) use plain Array
static func copy_matrix(src: Array) -> Array[Array]:
	var copy: Array[Array] = []
	for i in range(src.size()):
		var row: Array = []
		for j in range(src[i].size()):
			row.append(src[i][j])
		copy.append(row)
	return copy

static func hessenberg_reduce(m: Array[Array]) -> Array[Array]:
	var n := m.size()
	if n == 0:
		return m
	for k in range(n - 2):
		var sigma: float = 0.0
		for i in range(k + 1, n):
			sigma += m[i][k] * m[i][k]
		sigma = sqrt(sigma)

		if m[k + 1][k] >= 0:
			sigma = -sigma

		var v: Array = []
		for i in range(n):
			if i <= k:
				v.append(0.0)
			elif i == k + 1:
				v.append(m[i][k] + sigma)
			else:
				v.append(m[i][k])

		var v_norm_sq: float = 0.0
		for i in range(n):
			v_norm_sq += v[i] * v[i]

		if v_norm_sq < 1e-12:
			continue

		for j in range(n):
			var dot: float = 0.0
			for i in range(n):
				dot += v[i] * m[i][j]
			for i in range(n):
				m[i][j] -= 2.0 * v[i] * dot / v_norm_sq

		for i in range(n):
			var dot: float = 0.0
			for j in range(n):
				dot += m[i][j] * v[j]
			for j in range(n):
				m[i][j] -= 2.0 * dot * v[j] / v_norm_sq

	return m

static func qr_eigenvalues(hess: Array[Array], max_iter: int = 50) -> Array:
	var n := hess.size()
	var eigenvals: Array = []
	if n == 0:
		return eigenvals
	if n == 1:
		eigenvals.append(hess[0][0])
		return eigenvals

	# 带位移的 QR 迭代：对活跃子矩阵 [0..p] 做 QR sweep
	# 位移采用 Wilkinson 位移（对实矩阵收敛性优于 Rayleigh）
	var p: int = n - 1
	var iter_count: int = 0
	while p > 0 and iter_count < max_iter * n:
		iter_count += 1

		# 检查次对角元是否可忽略 -> deflation
		for i in range(p, 0, -1):
			if abs(hess[i][i - 1]) < 1e-12 * (abs(hess[i - 1][i - 1]) + abs(hess[i][i])):
				hess[i][i - 1] = 0.0
				if i == p:
					p -= 1
		if p <= 0:
			break

		# Wilkinson 位移：用右下角 2x2 子矩阵的特征值
		var a: float = hess[p - 1][p - 1]
		var b: float = hess[p - 1][p]
		var c: float = hess[p][p - 1]
		var d: float = hess[p][p]
		var tr: float = a + d
		var det: float = a * d - b * c
		var disc: float = tr * tr - 4.0 * det
		var sq: float = sqrt(maxf(disc, 0.0))
		var ev1: float = (tr + sq) * 0.5
		var ev2: float = (tr - sq) * 0.5
		# 选离 d 较近的特征值作为位移
		var shift: float = ev1 if abs(ev1 - d) < abs(ev2 - d) else ev2

		# 位移应用到活跃子矩阵的对角线
		for i in range(p + 1):
			hess[i][i] -= shift

		# QR sweep via Givens 旋转
		var cos_arr: Array = []
		var sin_arr: Array = []
		for i in range(p):
			var denom: float = sqrt(hess[i][i] * hess[i][i] + hess[i + 1][i] * hess[i + 1][i])
			if denom < 1e-12:
				cos_arr.append(1.0)
				sin_arr.append(0.0)
			else:
				cos_arr.append(hess[i][i] / denom)
				sin_arr.append(hess[i + 1][i] / denom)

			for j in range(p + 1):
				var t1: float = cos_arr[i] * hess[i][j] + sin_arr[i] * hess[i + 1][j]
				var t2: float = -sin_arr[i] * hess[i][j] + cos_arr[i] * hess[i + 1][j]
				hess[i][j] = t1
				hess[i + 1][j] = t2

		for i in range(p):
			for j in range(p + 1):
				var t1: float = cos_arr[i] * hess[j][i] + sin_arr[i] * hess[j][i + 1]
				var t2: float = -sin_arr[i] * hess[j][i] + cos_arr[i] * hess[j][i + 1]
				hess[j][i] = t1
				hess[j][i + 1] = t2

		# 恢复位移
		for i in range(p + 1):
			hess[i][i] += shift

	eigenvals.clear()
	for i in range(n):
		eigenvals.append(hess[i][i])

	return eigenvals
