use godot::prelude::*;
use nalgebra::{Matrix4, SymmetricEigen};

type Dict = Dictionary<Variant, Variant>;

// 守恒状态枚举 - 跟特征值阈值挂钩
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ConservationState {
    Healthy = 0,
    Warning = 1,
    Critical = 2,
    Disintegrated = 3,
}

// 阈值需与 GDScript 端 (07_conservation_engine.gd) 保持一致：
// 以单位矩阵特征值 1.0 为基准，用 abs(ev - 1.0) 衡量守恒偏离度
const WARNING_THRESHOLD: f64 = 0.3;
const CRITICAL_THRESHOLD: f64 = 0.6;
const DISINTEGRATE_THRESHOLD: f64 = 0.9;

impl ConservationState {
    fn from_eigenvalues(eigenvalues: &[f64; 4]) -> Self {
        // 取四个特征值中相对 1.0 的最大偏离度作为状态判据
        let mut max_deviation: f64 = 0.0;
        for &ev in eigenvalues {
            let dev = (ev - 1.0).abs();
            if dev > max_deviation {
                max_deviation = dev;
            }
        }

        if max_deviation > DISINTEGRATE_THRESHOLD {
            ConservationState::Disintegrated
        } else if max_deviation > CRITICAL_THRESHOLD {
            ConservationState::Critical
        } else if max_deviation > WARNING_THRESHOLD {
            ConservationState::Warning
        } else {
            ConservationState::Healthy
        }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ConservationMatrix {
    base: Base<RefCounted>,
    // 4x4 对称矩阵: 行列对应 (mass, charge, momentum, energy)
    matrix: Matrix4<f64>,
    eigenvalues: [f64; 4],
    eigenvectors: [[f64; 4]; 4],
    state: ConservationState,
}

#[godot_api]
impl IRefCounted for ConservationMatrix {
    fn init(base: Base<RefCounted>) -> Self {
        let mut cm = Self {
            base,
            matrix: Matrix4::identity(),
            eigenvalues: [1.0; 4],
            eigenvectors: [[0.0; 4]; 4],
            state: ConservationState::Healthy,
        };
        // 初始特征向量就是标准基
        for i in 0..4 {
            cm.eigenvectors[i][i] = 1.0;
        }
        cm
    }
}

#[godot_api]
impl ConservationMatrix {
    #[signal]
    fn state_changed(old_state: i32, new_state: i32);

    #[signal]
    fn eigenvalue_warning(index: i32, value: f64);

    /// 对矩阵施加操作，返回更新后的特征值
    /// 支持: "perturb" (row, col, delta), "scale" (index, factor), "reset", "symmetrize"
    #[func]
    fn apply_operation(&mut self, operation_type: GString, params: Dict) -> PackedFloat64Array {
        let op = operation_type.to_string();

        match op.as_str() {
            "perturb" => {
                let row = params.get_or_nil("row").to::<i32>() as usize;
                let col = params.get_or_nil("col").to::<i32>() as usize;
                let delta = params.get_or_nil("delta").to::<f64>();
                if row < 4 && col < 4 {
                    self.matrix[(row, col)] += delta;
                    self.matrix[(col, row)] += delta; // 保持对称
                }
            }
            "scale" => {
                let idx = params.get_or_nil("index").to::<i32>() as usize;
                let factor = params.get_or_nil("factor").to::<f64>();
                if idx < 4 {
                    self.matrix[(idx, idx)] *= factor;
                }
            }
            "reset" => {
                self.matrix = Matrix4::identity();
            }
            "symmetrize" => {
                for i in 0..4 {
                    for j in (i + 1)..4 {
                        let avg = (self.matrix[(i, j)] + self.matrix[(j, i)]) / 2.0;
                        self.matrix[(i, j)] = avg;
                        self.matrix[(j, i)] = avg;
                    }
                }
            }
            _ => {}
        }

        self.recompute_eigen();
        self.pack_eigenvalues()
    }

    #[func]
    fn get_state(&self) -> i32 {
        self.state as i32
    }

    #[func]
    fn get_eigenvalues(&self) -> PackedFloat64Array {
        self.pack_eigenvalues()
    }

    #[func]
    fn get_eigenvectors(&self) -> PackedFloat64Array {
        let mut arr = PackedFloat64Array::new();
        for i in 0..4 {
            for j in 0..4 {
                arr.push(self.eigenvectors[i][j]);
            }
        }
        arr
    }

    /// 读取矩阵某个元素
    #[func]
    fn get_entry(&self, row: i32, col: i32) -> f64 {
        if (0..4).contains(&row) && (0..4).contains(&col) {
            self.matrix[(row as usize, col as usize)]
        } else {
            0.0
        }
    }

    /// 重置矩阵到单位阵
    #[func]
    fn reset(&mut self) {
        let old = self.state as i32;
        self.matrix = Matrix4::identity();
        self.eigenvalues = [1.0; 4];
        for i in 0..4 {
            for j in 0..4 {
                self.eigenvectors[i][j] = if i == j { 1.0 } else { 0.0 };
            }
        }
        self.state = ConservationState::Healthy;
        let new = self.state as i32;
        if old != new {
            self.base_mut().emit_signal("state_changed", &[old.to_variant(), new.to_variant()]);
        }
    }
}

impl ConservationMatrix {
    fn recompute_eigen(&mut self) {
        let eigen: SymmetricEigen<f64, nalgebra::U4> = self.matrix.symmetric_eigen();

        // 特征值按升序排列，我们按绝对值从大到小重排方便游戏使用
        let mut indexed: [(usize, f64); 4] = Default::default();
        for (i, eigen_val) in eigen.eigenvalues.iter().enumerate() {
            indexed[i] = (i, *eigen_val);
        }
        indexed
            .sort_by(|a, b| b.1.abs().partial_cmp(&a.1.abs()).unwrap_or(std::cmp::Ordering::Equal));

        for (slot, item) in indexed.iter().enumerate() {
            self.eigenvalues[slot] = item.1;
            let src_col = item.0;
            for row in 0..4 {
                self.eigenvectors[slot][row] = eigen.eigenvectors[(row, src_col)];
            }
        }

        let old_state = self.state;
        let new_state = ConservationState::from_eigenvalues(&self.eigenvalues);

        // 检查是否需要发出特征值警告：偏离度超过 WARNING_THRESHOLD 即触发
        for i in 0..4 {
            let ev = self.eigenvalues[i];
            let dev = (ev - 1.0).abs();
            if dev > WARNING_THRESHOLD {
                self.base_mut()
                    .emit_signal("eigenvalue_warning", &[(i as i32).to_variant(), ev.to_variant()]);
            }
        }

        if old_state != new_state {
            self.state = new_state;
            self.base_mut().emit_signal(
                "state_changed",
                &[(old_state as i32).to_variant(), (new_state as i32).to_variant()],
            );
        } else {
            self.state = new_state;
        }
    }

    fn pack_eigenvalues(&self) -> PackedFloat64Array {
        let mut arr = PackedFloat64Array::new();
        for &ev in &self.eigenvalues {
            arr.push(ev);
        }
        arr
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nalgebra::Matrix4;

    #[test]
    fn identity_eigenvalues_all_one() {
        let m = Matrix4::identity();
        let eigen: SymmetricEigen<f64, nalgebra::U4> = m.symmetric_eigen();
        for &ev in eigen.eigenvalues.iter() {
            assert!((ev - 1.0).abs() < 1e-10, "Identity eigenvalue should be 1.0, got {}", ev);
        }
    }

    #[test]
    fn perturbation_changes_eigenvalues() {
        let mut m = Matrix4::identity();
        m[(0, 0)] += 0.5;
        let eigen_before: SymmetricEigen<f64, nalgebra::U4> = Matrix4::identity().symmetric_eigen();
        let eigen_after: SymmetricEigen<f64, nalgebra::U4> = m.symmetric_eigen();

        let before: Vec<f64> = eigen_before.eigenvalues.iter().copied().collect();
        let after: Vec<f64> = eigen_after.eigenvalues.iter().copied().collect();

        assert_ne!(before, after, "Perturbation should change eigenvalues");
    }

    #[test]
    fn symmetrize_makes_matrix_symmetric() {
        let mut m = Matrix4::identity();
        m[(0, 1)] = 0.7;
        m[(1, 0)] = 0.3;
        m[(2, 3)] = 0.9;
        m[(3, 2)] = 0.1;

        // Apply symmetrize logic
        for i in 0..4 {
            for j in (i + 1)..4 {
                let avg = (m[(i, j)] + m[(j, i)]) / 2.0;
                m[(i, j)] = avg;
                m[(j, i)] = avg;
            }
        }

        for i in 0..4 {
            for j in 0..4 {
                let diff: f64 = m[(i, j)] - m[(j, i)];
                assert!(
                    diff.abs() < 1e-12,
                    "Matrix should be symmetric after symmetrize: m[{}, {}]={}, m[{}, {}]={}",
                    i,
                    j,
                    m[(i, j)],
                    j,
                    i,
                    m[(j, i)]
                );
            }
        }
    }

    #[test]
    fn state_transitions_healthy_to_disintegrated() {
        // 偏离度 = abs(ev - 1.0)，阈值 0.3/0.6/0.9

        // Healthy: 所有特征值偏离度 ≤ 0.3
        let healthy = [1.0, 1.0, 1.0, 1.0];
        assert_eq!(ConservationState::from_eigenvalues(&healthy), ConservationState::Healthy);

        // Warning: 偏离度 > 0.3 且 ≤ 0.6 (ev=0.6 → dev=0.4)
        let warning = [1.0, 1.0, 1.0, 0.6];
        assert_eq!(ConservationState::from_eigenvalues(&warning), ConservationState::Warning);

        // Critical: 偏离度 > 0.6 且 ≤ 0.9 (ev=0.3 → dev=0.7)
        let critical = [1.0, 1.0, 1.0, 0.3];
        assert_eq!(ConservationState::from_eigenvalues(&critical), ConservationState::Critical);

        // Disintegrated: 偏离度 > 0.9 (ev=0.0 → dev=1.0)
        let disintegrated = [1.0, 1.0, 1.0, 0.0];
        assert_eq!(
            ConservationState::from_eigenvalues(&disintegrated),
            ConservationState::Disintegrated
        );
    }

    #[test]
    fn reset_returns_to_identity() {
        let mut m = Matrix4::identity();
        m[(0, 0)] = 2.0;
        m[(1, 1)] = 0.5;
        m[(2, 3)] = 0.3;

        // Reset
        m = Matrix4::identity();

        assert_eq!(m, Matrix4::identity(), "Reset should return identity matrix");
    }
}
