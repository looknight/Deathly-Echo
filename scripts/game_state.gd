extends Node
## 全局游戏状态

var wave: int = 0
var max_waves: int = 10
var kills: int = 0
var combo: int = 0
var combo_timer: float = 0.0
var map_index: int = 0
var player_class: String = "assault"
var game_won: bool = false

var MAP_NAMES: Array[String] = ["街道","老巷","广场","地铁站","车库","码头","医院","工地"]

func reset() -> void:
	wave = 0
	kills = 0
	combo = 0
	combo_timer = 0.0
	map_index = 0
	game_won = false
