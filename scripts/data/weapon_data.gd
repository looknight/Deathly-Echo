extends Resource
class_name WeaponData
## 武器数值定义（数据资源）
##
## 每个 `.tres` 描述一把枪的静态数值，运行时由 `player._load_weapon_table()` 读取。
## 改数值只需改这里的资源，不必动代码；`player.gd` 里的 FALLBACK_WEAPONS 仅作兜底。

@export var id: String = ""              # 必须与文件名一致（加载时会校验）
@export var display_name: String = ""    # HUD 与换枪提示显示的名字
@export var damage: float = 0.0          # 单发/单弹丸基础伤害
@export var mag_size: int = 1            # 弹匣容量（弹匣扩容卡在此基线上乘倍率）
@export var reserve: int = 0             # 初始备弹
@export var fire_interval: float = 0.3   # 两发之间的最小间隔（秒）
@export var spread: float = 0.02         # 散射半径（方向向量偏移量）
@export var pellets: int = 1             # 每次射击的弹丸数
@export var automatic: bool = false      # 按住左键是否连发
