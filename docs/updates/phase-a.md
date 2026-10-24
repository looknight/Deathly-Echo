# 阶段 A · 工程化与打包

**状态：✅ 已完成** · 2026-10-24 · 版本 `v0.9.0` · 提交 `c11b5b3` `f8b2f20` `6bf49ab` `c0c3560`

---

## 背景

到 v0.9.0 时玩法已闭环，但工程处于「只在这台机器上能跑」的状态：

- 25 个文件未提交，最近一次提交停在 4 天前的「波次层完成」
- 仓库里没有 `export_presets.cfg`，无法一键导出
- 项目没有版本号，出问题无法定位是哪个版本
- 渲染设置全是引擎默认（1920×1080、MSAA 关闭之外无调优），未针对 MX550
- 存档只有一个 JSON，没有版本字段，写坏就全丢

本阶段不做任何玩法改动，目标是**把项目变成可以打包发出、并且出问题能查的状态**。

## 改动清单

| 文件 | 改动 |
|---|---|
| `project.godot` | 新增 `config/version="0.9.0"`；`[rendering]` 增加 `anti_aliasing/quality/msaa_3d=1`（MSAA 2x）与 `scaling_3d/scale=0.85` |
| `export_presets.cfg` | **新增**。Windows Desktop 预设，`export_path="build/ZombieFPS.exe"`，`binary_format/embed_pck=true`（单文件分发），关闭控制台包装 |
| `scripts/hud.gd` | **新增 F3 调试覆盖层**：FPS / 波次 / 敌人数 / draw call / 对象数 / 显存，0.25 秒节流，暂停与结算界面下同样可切 |
| `scripts/game_state.gd` | 新增 `SAVE_VERSION=2` 与 `version` 字段；写入前备份到 `zombie_save.bak.json`；新增 `_read_save()`，主档损坏时自动回退备份 |
| `.gitignore` | 增加 `build/`、`*.exe`、`*.pck`（导出产物）、`.workbuddy/`（本地工作记录） |
| `scripts/player.gd` | 行尾统一为 LF（原文件混入 903 处 CRLF，其余文件均为 LF） |
| `README.md` | 全量重写为 v0.9.0 真实状态（此前线上版本还写着火焰枪、无升级系统） |
| `docs/updates/*` | **新增**。本套阶段文档 |

## 验收结果

| 项 | 结果 |
|---|---|
| 提交状态 | 工作区干净，`6d768916..c0c3560 master -> master` 已快进推送 |
| 版本号 | `config/version="0.9.0"`，与 tag 对应 |
| 标签 | `v0.9.0` → `e97cd1a`，且仍在主线历史上 |
| 导出预设 | 编辑器可识别；`build/ZombieFPS.exe` 单文件，无需附带 `.pck` |
| 渲染设置 | Godot 保存时保留了 `msaa_3d=1` 与 `scaling_3d/scale=0.85`（省略了等于默认值的 `scaling_3d/mode=0`），说明键名被正确解析 |
| 存档兼容 | 旧存档（无 `version` 字段）按 1 处理，缺字段走默认值，不会报错 |
| 静态检查 | 14 个脚本 0 结构性错误（引号 / 行首空格 / 重复函数） |
| 远程核对 | GitHub 上 README 与本地逐字一致 |

## 已知遗留

- **未做运行时验证**：本阶段全程只有静态检查，没有在 Godot 里实跑。首次运行需人工确认五处（开镜遮罩、三选一排版、双 BOSS 血条、结算破纪录、拾取音不刷屏）
- 导出前必须先安装与编辑器版本一致的导出模板，否则 Export 会直接报模板缺失
- `F3` 覆盖层的 draw call 在 Compatibility 渲染后端下返回 0（当前用 Forward+，不受影响）

## 对后续阶段的影响

- F3 覆盖层是阶段 E 的**度量工具**：网格合并前后用同一场景对比 draw call，避免凭感觉判断
- `config/version` 是后续每个阶段的版本锚点，建议每次对外发包都递增
