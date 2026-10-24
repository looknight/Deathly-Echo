# 阶段 C · 拆分 HUD

**状态：⬜ 未开始** · 预计成本 2~3 天 · 风险 中（坐标回归）

---

## 背景

`scripts/hud.gd` 目前 **716 行 / 34 个函数**，一个文件里塞了九件事：

| 职责 | 相关成员 |
|---|---|
| 血量/弹药/波次/击杀文本 | `hp_bar` `ammo_cur` `wave_txt` `kill_txt` 等 12 个 Label |
| 自绘准星 + 命中标记 | `crosshair_node` `_draw_crosshair()` `kick_crosshair()` |
| 濒死暗角 | `vignette_overlay` `_draw_vignette()` `vignette_alpha` |
| 开镜遮罩 | `scope_overlay` `_draw_scope()` |
| 暂停面板（含 3 项设置） | `pause_panel` `_draw_pause()` `settings_row` `_adjust_setting()` |
| 三选一升级卡 | `upgrade_panel` `_draw_upgrades()` `_wrap_text()` `_pick_upgrade()` |
| 死亡结算 | `gameover_panel` `_draw_gameover()` `_favorite_upgrade()` `_format_time()` |
| 多 BOSS 血条 | `boss_panels/bars/names` `_ensure_boss_panels()` `_update_boss_bars()` |
| 开局提示 / 调试覆盖层 | `hint_label` `debug_label` `_tick_debug()` |

`_process` 单函数 92 行，同时负责刷新文本、计时、暗角、血条、提示淡出。任何一处 UI 改动都要通读全文。

## 目标结构

```
scripts/ui/
├── hud_root.gd          # 只做连线与 _process 调度（目标 < 120 行）
├── crosshair.gd         # 准星 + 命中标记 + 开火扩散
├── scope_overlay.gd     # 开镜镜片
├── vignette.gd          # 濒死暗角
├── boss_bars.gd         # 多 BOSS 血条（含面板复制与排位）
├── upgrade_panel.gd     # 三选一 + 自动折行 + 输入接管
├── pause_panel.gd       # 暂停面板 + 设置项
├── gameover_panel.gd    # 结算卡片 + 纪录对比
└── hud_bars.gd          # 血量 / 弹药 / 波次 / 击杀等常驻文本
```

每个面板都是独立 `Control`，通过 `queue_redraw()` 自绘，互不 import。`hud_root` 负责：找到玩家、每帧把数据推给各子面板、把输入转给当前激活的面板。

## 实施步骤

### C1 · 先拆「无状态」的两个

`crosshair.gd`、`vignette.gd` 不依赖其他面板，只吃 `player.hp` 与几个数值，风险最低。拆完立刻比对截图。

### C2 · 拆结算与升级面板

这两个面板最独立（只在特定时刻显示），但涉及输入接管，需要一起改 `_input` 的分发顺序。

### C3 · 拆暂停面板与 BOSS 血条

暂停面板与设置项耦合（`settings_row` 状态），BOSS 血条涉及动态复制面板，放在后期。

### C4 · 收尾

`hud_root.gd` 只保留：`_ready` 建面板 → `_process` 推数据 → `_input` 分发 → 对外 API（`show_center` / `show_hint` / `set_bosses` / `show_upgrades` / `show_scope` / `kick_crosshair`）。这些 API 名字**保持不变**，避免改动 `player.gd` 与 `wave_manager.gd`。

## 验收标准

- [ ] 逐屏截图对比（1280×720 与 1920×1080 各一轮）：主 HUD / 开镜 / 暂停 / 三选一 / 结算 / 双 BOSS / 濒死暗角 / 开局提示
- [ ] `hud.gd` 拆分后 `hud_root.gd` ≤ 150 行，且没有任何 `_draw_*` 函数
- [ ] 对外 API 签名不变：`grep -rn 'hud\.' scripts/` 的调用点无需修改
- [ ] F3 调试覆盖层仍可用，暂停时也能切
- [ ] 输入优先级不变：三选一 > 暂停 > 玩法

## 风险与回滚

**中风险，主要是坐标回归**——所有面板都用绝对像素画在 `Control` 上，拆文件不会自动改坐标，但 `_overlay_size()` 的取法如果变了就会错位。缓解办法：C1 拆完后立刻截图比对，再继续下一步；每步单独提交，可单独 revert。

不做的事：不改成 `Label`/`ProgressBar` 节点树。现在的手绘风格是统一的，换成节点反而要重做主题。
