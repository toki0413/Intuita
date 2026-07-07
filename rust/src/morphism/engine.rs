use godot::prelude::*;

type Dict = Dictionary<Variant, Variant>;

// 态射类型 - 覆盖范畴论中常见的态射类别
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum MorphismType {
    Transformation = 0,
    Restriction = 1,
    Embedding = 2,
    Quotient = 3,
    Composite = 4,
    Approximation = 5,
    Projection = 6,
    Surrogate = 7,
}

impl MorphismType {
    fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Transformation),
            1 => Some(Self::Restriction),
            2 => Some(Self::Embedding),
            3 => Some(Self::Quotient),
            4 => Some(Self::Composite),
            5 => Some(Self::Approximation),
            6 => Some(Self::Projection),
            7 => Some(Self::Surrogate),
            _ => None,
        }
    }
}

pub struct MorphismResult {
    pub result_type: MorphismType,
    pub invariants_kept: Vec<String>,
    pub invariants_lost: Vec<String>,
    pub invariants_introduced: Vec<String>,
    pub is_invertible: bool,
}

impl MorphismResult {
    fn to_dict(&self) -> Dict {
        let mut dict = Dict::new();

        dict.set("result_type", self.result_type as i32);
        dict.set("is_invertible", self.is_invertible);

        let mut kept = PackedStringArray::new();
        for s in &self.invariants_kept {
            kept.push(&GString::from(s.as_str()));
        }
        dict.set("invariants_kept", &kept);

        let mut lost = PackedStringArray::new();
        for s in &self.invariants_lost {
            lost.push(&GString::from(s.as_str()));
        }
        dict.set("invariants_lost", &lost);

        let mut introduced = PackedStringArray::new();
        for s in &self.invariants_introduced {
            introduced.push(&GString::from(s.as_str()));
        }
        dict.set("invariants_introduced", &introduced);

        dict
    }
}

// 纯函数: 同类型组合
fn compose_same(t: MorphismType) -> MorphismResult {
    match t {
        MorphismType::Transformation => MorphismResult {
            result_type: MorphismType::Composite,
            invariants_kept: vec!["all".into()],
            invariants_lost: vec![],
            invariants_introduced: vec![],
            is_invertible: true,
        },
        MorphismType::Restriction => MorphismResult {
            result_type: MorphismType::Restriction,
            invariants_kept: vec!["intersection".into()],
            invariants_lost: vec!["individual_scope".into()],
            invariants_introduced: vec![],
            is_invertible: false,
        },
        MorphismType::Embedding => MorphismResult {
            result_type: MorphismType::Embedding,
            invariants_kept: vec!["original_structure".into()],
            invariants_lost: vec![],
            invariants_introduced: vec!["extended_context".into()],
            is_invertible: false,
        },
        MorphismType::Quotient => MorphismResult {
            result_type: MorphismType::Quotient,
            invariants_kept: vec!["equivalence_classes".into()],
            invariants_lost: vec!["class_representatives".into()],
            invariants_introduced: vec!["coarser_equivalence".into()],
            is_invertible: false,
        },
        MorphismType::Composite => MorphismResult {
            result_type: MorphismType::Composite,
            invariants_kept: vec!["all".into()],
            invariants_lost: vec![],
            invariants_introduced: vec![],
            is_invertible: true,
        },
        MorphismType::Approximation => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["approximate_properties".into()],
            invariants_lost: vec!["precision".into()],
            invariants_introduced: vec!["compounded_error".into()],
            is_invertible: false,
        },
        MorphismType::Projection => MorphismResult {
            result_type: MorphismType::Projection,
            invariants_kept: vec!["projected_subspace".into()],
            invariants_lost: vec!["orthogonal_components".into()],
            invariants_introduced: vec![],
            is_invertible: false,
        },
        MorphismType::Surrogate => MorphismResult {
            result_type: MorphismType::Surrogate,
            invariants_kept: vec!["statistical_moments".into()],
            invariants_lost: vec!["deterministic_structure".into()],
            invariants_introduced: vec!["surrogate_distribution".into()],
            is_invertible: false,
        },
    }
}

// 纯函数: Transformation作为恒等态射提升
fn lift_type(t: MorphismType) -> MorphismResult {
    MorphismResult {
        result_type: t,
        invariants_kept: vec!["all_original".into()],
        invariants_lost: vec![],
        invariants_introduced: vec![],
        is_invertible: matches!(t, MorphismType::Transformation | MorphismType::Composite),
    }
}

// 纯函数: 默认结果
fn default_result() -> MorphismResult {
    MorphismResult {
        result_type: MorphismType::Approximation,
        invariants_kept: vec!["structure".into()],
        invariants_lost: vec!["precision".into()],
        invariants_introduced: vec!["approximation_error".into()],
        is_invertible: false,
    }
}

// 纯函数: 核心组合逻辑 - 顺序敏感
pub fn compute_compose(a: MorphismType, b: MorphismType) -> MorphismResult {
    // 同类型组合
    if a == b {
        return compose_same(a);
    }

    // Transformation 充当恒等态射的角色
    if a == MorphismType::Transformation {
        return lift_type(b);
    }
    if b == MorphismType::Transformation {
        return lift_type(a);
    }

    // 非交换的核心规则
    match (a, b) {
        // Restriction 在前 → 投影效应 (先缩小再变换 = 投影)
        (MorphismType::Restriction, MorphismType::Embedding) => MorphismResult {
            result_type: MorphismType::Projection,
            invariants_kept: vec!["subspace_structure".into()],
            invariants_lost: vec!["global_structure".into()],
            invariants_introduced: vec![],
            is_invertible: false,
        },
        // Embedding 在前 → 近似效应 (先嵌入再限制 = 近似)
        (MorphismType::Embedding, MorphismType::Restriction) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["local_structure".into()],
            invariants_lost: vec!["exact_values".into()],
            invariants_introduced: vec!["approximation_error".into()],
            is_invertible: false,
        },
        // Quotient 在前 → 投影 (先商化再嵌入 = 投影到等价类)
        (MorphismType::Quotient, MorphismType::Embedding) => MorphismResult {
            result_type: MorphismType::Projection,
            invariants_kept: vec!["equivalence_classes".into()],
            invariants_lost: vec!["representative_detail".into()],
            invariants_introduced: vec![],
            is_invertible: false,
        },
        // Embedding 在前 → 近似 (先嵌入再商化 = 信息损失近似)
        (MorphismType::Embedding, MorphismType::Quotient) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["topological_invariants".into()],
            invariants_lost: vec!["metric_properties".into()],
            invariants_introduced: vec!["quotient_structure".into()],
            is_invertible: false,
        },
        // Surrogate 吸收左侧 (代理态射是终极退化)
        (MorphismType::Surrogate, _) => MorphismResult {
            result_type: MorphismType::Surrogate,
            invariants_kept: vec!["statistical_moments".into()],
            invariants_lost: vec!["exact_values".into(), "causal_structure".into()],
            invariants_introduced: vec!["surrogate_distribution".into()],
            is_invertible: false,
        },
        // Surrogate 在右侧 → 近似 (先用别的再用代理 = 近似)
        (_, MorphismType::Surrogate) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["statistical_properties".into()],
            invariants_lost: vec!["deterministic_structure".into()],
            invariants_introduced: vec!["stochastic_approximation".into()],
            is_invertible: false,
        },
        // Projection 吸收左侧
        (MorphismType::Projection, _) => MorphismResult {
            result_type: MorphismType::Projection,
            invariants_kept: vec!["projected_subspace".into()],
            invariants_lost: vec!["orthogonal_components".into()],
            invariants_introduced: vec![],
            is_invertible: false,
        },
        // Projection 在右侧 → 近似
        (_, MorphismType::Projection) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["projection_invariants".into()],
            invariants_lost: vec!["full_dimensionality".into()],
            invariants_introduced: vec!["projection_artifacts".into()],
            is_invertible: false,
        },
        // Restriction ∘ Quotient = Surrogate (双重信息损失)
        (MorphismType::Restriction, MorphismType::Quotient) => MorphismResult {
            result_type: MorphismType::Surrogate,
            invariants_kept: vec!["coarse_statistics".into()],
            invariants_lost: vec!["fine_structure".into(), "equivalence_detail".into()],
            invariants_introduced: vec!["surrogate_approximation".into()],
            is_invertible: false,
        },
        // Quotient ∘ Restriction = Approximation
        (MorphismType::Quotient, MorphismType::Restriction) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["quotient_invariants".into()],
            invariants_lost: vec!["subspace_detail".into()],
            invariants_introduced: vec!["restricted_quotient".into()],
            is_invertible: false,
        },
        // Approximation ∘ 任何 = Approximation (近似是传染性的)
        (MorphismType::Approximation, _) | (_, MorphismType::Approximation) => MorphismResult {
            result_type: MorphismType::Approximation,
            invariants_kept: vec!["approximate_structure".into()],
            invariants_lost: vec!["exact_values".into()],
            invariants_introduced: vec!["cumulative_error".into()],
            is_invertible: false,
        },
        // Composite ∘ X 或 X ∘ Composite
        (MorphismType::Composite, other) | (other, MorphismType::Composite) => {
            compute_compose(other, other)
        }
        // 兜底
        _ => default_result(),
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct MorphismEngine {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for MorphismEngine {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl MorphismEngine {
    /// 组合两个态射 - 注意: 非交换! compose(a, b) != compose(b, a)
    /// a 先作用，b 后作用 (即 b ∘ a)
    #[func]
    fn compose(&self, type_a: i32, type_b: i32) -> Dict {
        let a = match MorphismType::from_i32(type_a) {
            Some(t) => t,
            None => return default_result().to_dict(),
        };
        let b = match MorphismType::from_i32(type_b) {
            Some(t) => t,
            None => return default_result().to_dict(),
        };

        compute_compose(a, b).to_dict()
    }

    /// 检查给定参数下的态射是否可逆
    #[func]
    fn check_invertibility(&self, morph_type: i32, params: Dict) -> bool {
        let mt = match MorphismType::from_i32(morph_type) {
            Some(t) => t,
            None => return false,
        };

        // 如果参数明确标注了双射，直接可逆
        if !params.get_or_nil("bijective").is_nil() && params.get_or_nil("bijective").to::<bool>() {
            return true;
        }

        matches!(mt, MorphismType::Transformation | MorphismType::Composite)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compose_transformation_transformation_is_composite_invertible() {
        let result = compute_compose(MorphismType::Transformation, MorphismType::Transformation);
        assert_eq!(result.result_type, MorphismType::Composite);
        assert!(result.is_invertible);
    }

    #[test]
    fn compose_restriction_embedding_is_projection_not_invertible() {
        let result = compute_compose(MorphismType::Restriction, MorphismType::Embedding);
        assert_eq!(result.result_type, MorphismType::Projection);
        assert!(!result.is_invertible);
    }

    #[test]
    fn compose_embedding_restriction_is_approximation_not_invertible() {
        let result = compute_compose(MorphismType::Embedding, MorphismType::Restriction);
        assert_eq!(result.result_type, MorphismType::Approximation);
        assert!(!result.is_invertible);
    }

    #[test]
    fn compose_is_not_commutative() {
        let ab = compute_compose(MorphismType::Restriction, MorphismType::Embedding);
        let ba = compute_compose(MorphismType::Embedding, MorphismType::Restriction);
        assert_ne!(
            ab.result_type, ba.result_type,
            "compose(Restriction, Embedding) should differ from compose(Embedding, Restriction)"
        );
    }

    #[test]
    fn surrogate_absorbs_left_side() {
        let rights = [
            MorphismType::Restriction,
            MorphismType::Embedding,
            MorphismType::Quotient,
            MorphismType::Composite,
            MorphismType::Approximation,
            MorphismType::Projection,
        ];
        for right in rights {
            let result = compute_compose(MorphismType::Surrogate, right);
            assert_eq!(
                result.result_type,
                MorphismType::Surrogate,
                "Surrogate on left should absorb right={:?}",
                right
            );
        }
    }

    #[test]
    fn approximation_is_infectious() {
        // Approximation on left
        let left = compute_compose(MorphismType::Approximation, MorphismType::Restriction);
        assert_eq!(left.result_type, MorphismType::Approximation);

        // Approximation on right
        let right = compute_compose(MorphismType::Embedding, MorphismType::Approximation);
        assert_eq!(right.result_type, MorphismType::Approximation);
    }
}
