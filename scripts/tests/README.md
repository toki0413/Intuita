# Intuita 测试套件

使用 [gdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) 作为测试框架。

## 安装 gdUnit4

### 手动安装（推荐）

1. 下载 `v6.1.3`：
   https://github.com/godot-gdunit-labs/gdUnit4/archive/refs/tags/v6.1.3.zip
2. 解压到临时目录。
3. 将 `gdUnit4-6.1.3/addons/gdUnit4` 复制到项目根目录的 `addons/gdUnit4`。
4. 在 Godot 编辑器中启用插件：
   `Project -> Project Settings -> Plugins -> GdUnit4`

### 自动安装

如果当前环境网络可用，运行：

```powershell
.\scripts\tests\run_tests.ps1 -InstallGdUnit
```

## 运行测试

```powershell
# 运行 scripts/tests 下所有测试
.\scripts\tests\run_tests.ps1

# 或运行全部项目测试
.\scripts\tests\run_tests.ps1 -TestPath "res://"

# 指定 Godot 路径
.\scripts\tests\run_tests.ps1 -GodotPath "C:\Program Files\Godot 4.6\Godot_v4.6.3-stable_win64_console.exe"
```

也可以直接双击 `run_tests.bat`。

## 测试文件

| 文件 | 说明 |
|------|------|
| `verification_pipeline_test.gd` | 验证管线：autoload、层级枚举、消耗 |
| `level_data_test.gd` | 关卡数据：42 个关卡工厂方法完整性 |
| `conservation_engine_test.gd` | 守恒引擎：矩阵读写、特征值、状态判定 |

## 添加新测试

1. 在 `scripts/tests/` 下新建 `*_test.gd` 文件。
2. 继承 `GdUnitTestSuite`。
3. 方法名以 `test_` 开头。
4. 使用 gdUnit4 断言，例如：

```gdscript
extends GdUnitTestSuite

func test_example() -> void:
    assert_int(1 + 1).is_equal(2)
```
