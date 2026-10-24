# 阶段 B · 配置数据资源化

**状态：⬜ 未开始** · 预计成本 1~2 天 · 风险 低

---

## 背景

当前所有可调数值都写在脚本字典里，改一个数就要动代码，且无法被工具扫描、无法按语言替换文案：

| 数据 | 位置 | 规模 |
|---|---|---|
| `WEAPONS` / `CLASS_WEAPONS` / `weapon_order` | `player.gd` | 5 把武器 × 8 字段 + 3 套职业配置 |
| `UPGRADES` / `UPGRADE_POOL` / `META_UPGRADES` / `MAP_NAMES` | `game_state.gd` | 15 张卡 + 2 项永久升级 + 8 张地图名 |
| `WAVE_MODS` / `MAP_STYLES` / `ELITE_AFFIXES` | `wave_manager.gd` | 2 档波次修饰 + 8 套配色 + 3 条词缀 |
| `ELITE_AFFIXES`（词缀显示名） | `zombie.gd` | 与 `wave_manager.gd` **同名不同结构**，属重复定义 |

同类商业作（Gunfire Reborn / Roboquest）的武器与词条都是可编辑资产，策划改表即可上线；本阶段的目的是把这条链路打通。

## 目标

1. 用自定义 `Resource` 描述武器 / 卡牌 / 敌人，实例存为 `.tres`
2. 运行时代码只读资源，不再内置数值
3. 顺手消除 `ELITE_AFFIXES` 的双份定义

## 实施步骤（每步可独立提交）

### B1 · 定义资源类型（不动现有逻辑）

```gdscript
# scripts/data/weapon_data.gd
class_name WeaponData extends Resource
@export var id: String
@export var display_name: String
@export var damage: float
@export var mag_size: int
@export var reserve: int
@export var fire_interval: float
@export var spread: float
@export var pellets: int
@export var automatic: bool
```

同样处理 `upgrade_data.gd`（id / name / desc / 效果枚举 / 参数）与 `enemy_data.gd`（血量 / 速度 / 伤害 / 缩放 / 配色 / 行为类型）。

### B2 · 只迁移武器（试点）

- 在 `resources/weapons/` 下生成 5 个 `.tres`，数值照抄现有 `WEAPONS`
- `player.gd` 改为从 `resources/weapons/*.tres` 构建 `WEAPONS` 字典（键与字段名保持不变）
- **保留旧字典作为兜底**：资源缺失时回退，避免一处漏配导致游戏起不来

### B3 · 迁移卡牌

- `apply_upgrade()` 现在是一个 `match id` 的 15 分支；迁移时改为「效果枚举 + 参数」驱动，例如
  `{"effect": "damage_mult", "value": 0.20}`、`{"effect": "mag_mult", "value": 0.50}`
- 这是本阶段唯一有逻辑风险的改动，建议先只迁 5 张验证

### B4 · 迁移敌人与地图

- 敌人：`_configure_type()` 的 `match zombie_type` 改为读 `EnemyData`
- 地图：`MAP_STYLES` / `WAVE_MODS` 迁为 `resources/maps/*.tres`、`resources/waves/*.tres`

## 验收标准

- [ ] 修改 `resources/weapons/pistol.tres` 的伤害后运行，游戏内生效，无需改代码
- [ ] 删除某个 `.tres` 后游戏仍能启动（走兜底字典），并在控制台给出明确警告
- [ ] 存档不受影响（`version` 仍为 2，现有存档可直接读）
- [ ] `grep -rn 'ELITE_AFFIXES'` 只剩一处定义
- [ ] 14 个脚本静态检查 0 错误

## 风险与回滚

风险低，因为每一步都保留旧实现。回滚方式：`git revert` 单个步骤提交，或把资源读取开关（如 `USE_DATA_RESOURCES = false`）关掉。

## 为什么先做这一步

阶段 D 的敌人状态机需要「每种敌人有一份配置」。先把数据搬出代码，D 阶段才能做到「新增敌人 = 加一个 `.tres` + 一个行为脚本」，而不是再往 9 处 `if` 里加分支。
