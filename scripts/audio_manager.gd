extends Node
## 音频管理器（Autoload: AudioManager）
##
## 职责一：10 个 AudioStreamPlayer 组成 SFX 池，统一挂 "SFX" 总线，轮转取用。
## 职责二：所有音效都在这里用代码合成（零外部资源），启动时预生成一次缓存。
## 职责三：低频 Drone 环境音，挂独立的 "BGM" 总线并加低通滤波。

const POOL_SIZE: int = 10
const BUS_NAME: String = "SFX"
const BGM_BUS: String = "BGM"
const SAMPLE_RATE: int = 22050

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

# 预合成流（启动时生成一次，之后只做播放，避免运行时算波形）
var _sfx_explosion: AudioStreamWAV
var _sfx_footstep: AudioStreamWAV
var _sfx_growl: AudioStreamWAV
var _sfx_pickup: AudioStreamWAV
var _bgm_drone: AudioStreamWAV

var _bgm_player: AudioStreamPlayer
var _growl_lock: float = 0.0   # 全局限流：避免 30 只丧尸同时吼叫

func _ready() -> void:
	# 暂停时也要能播音效（暂停面板、升级卡），因此设为 ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_NAME)
	_ensure_bus(BGM_BUS, 220.0)
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_NAME
		add_child(p)
		_players.append(p)
	# 预合成
	_sfx_explosion = _synth_explosion()
	_sfx_footstep = _synth_footstep()
	_sfx_growl = _synth_growl()
	_sfx_pickup = _synth_pickup()
	_bgm_drone = _synth_drone()
	_start_bgm()

func _process(delta: float) -> void:
	if _growl_lock > 0.0:
		_growl_lock -= delta

func _ensure_bus(bus: String, lowpass_hz: float = 0.0) -> void:
	# 工程里没有该总线时自动创建；也可在编辑器 Audio 面板手动建同名总线以便调音量
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, "Master")
	if lowpass_hz > 0.0 and AudioServer.get_bus_effect_count(idx) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = lowpass_hz
		AudioServer.add_bus_effect(idx, lp)

# ===== 播放接口 =====
func play_sfx(stream: AudioStream, volume_db: float = -8.0, pitch_jitter: float = 0.08) -> void:
	if stream == null or _players.is_empty():
		return
	_play(stream, volume_db, 1.0 + randf_range(-pitch_jitter, pitch_jitter))

func play_explosion(pos: Variant = null, base_db: float = -4.0) -> void:
	# 传位置则按距离衰减：远处闷、近处炸
	var vol: float = base_db
	if pos is Vector3:
		var p = get_tree().get_first_node_in_group("player")
		if p != null and is_instance_valid(p) and p is Node3D:
			var p3: Node3D = p
			vol -= clampf(pos.distance_to(p3.global_position) * 0.7, 0.0, 24.0)
	_play(_sfx_explosion, vol, randf_range(0.92, 1.06))

func play_footstep(volume_db: float = -16.0) -> void:
	_play(_sfx_footstep, volume_db, randf_range(0.88, 1.12))

func play_pickup() -> void:
	_play(_sfx_pickup, -10.0, randf_range(0.97, 1.05))

func play_growl(volume_db: float = -18.0, pitch: float = 1.0) -> void:
	# 全局限流：0.55 秒内只允许一次低吼，否则尸潮会变成一片噪音
	if _growl_lock > 0.0:
		return
	_growl_lock = 0.55
	_play(_sfx_growl, volume_db, clampf(pitch, 0.7, 1.4))

func _play(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _start_bgm() -> void:
	if _bgm_drone == null or _bgm_player != null:
		return
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.stream = _bgm_drone
	_bgm_player.bus = BGM_BUS
	_bgm_player.volume_db = -15.0
	add_child(_bgm_player)
	_bgm_player.play()

## 供外部查询当前池大小（调试用）
func pool_size() -> int:
	return _players.size()

# ===== 波形合成 =====
# 统一用 22.05kHz / 16bit / 单声道，体积小、NPC 音效足够
func _make_wav(samples: PackedFloat32Array, rate: int, loop: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data[i * 2] = v & 0xFF          # 取低字节（负数靠补码）
		data[i * 2 + 1] = (v >> 8) & 0xFF
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav

func _synth_explosion() -> AudioStreamWAV:
	# 低频正弦 70→28Hz 扫频 + 白噪声，指数衰减 0.6s
	var n: int = int(SAMPLE_RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var body_env: float = exp(-t * 5.5)
		var noise_env: float = exp(-t * 16.0)
		var f: float = lerpf(72.0, 26.0, clampf(t / 0.45, 0.0, 1.0))
		phase += TAU * f / float(SAMPLE_RATE)
		var low: float = sin(phase)
		var noise: float = randf() * 2.0 - 1.0
		s[i] = (low * 0.80 + noise * 0.55) * body_env * 0.9 + noise * noise_env * 0.25
	return _make_wav(s, SAMPLE_RATE)

func _synth_footstep() -> AudioStreamWAV:
	# 35ms 的低频噪声闷响：噪声 * 极快衰减，再乘一点低频正弦给它"落地感"
	var n: int = int(SAMPLE_RATE * 0.035)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-t * 110.0)
		phase += TAU * 95.0 / float(SAMPLE_RATE)
		var noise: float = randf() * 2.0 - 1.0
		s[i] = (noise * 0.55 + sin(phase) * 0.45) * env * 0.6
	return _make_wav(s, SAMPLE_RATE)

func _synth_growl() -> AudioStreamWAV:
	# 58→44Hz 锯齿波 + 4.5Hz 慢颤音 + 一点气声噪声，两端淡入淡出
	var dur: float = 1.1
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var vib: float = 1.0 + 0.07 * sin(TAU * 4.5 * t)
		var f: float = lerpf(58.0, 44.0, t / dur) * vib
		phase += TAU * f / float(SAMPLE_RATE)
		var saw: float = fmod(phase / TAU, 1.0) * 2.0 - 1.0
		var breath: float = randf() * 2.0 - 1.0
		var env: float = minf(t / 0.14, 1.0) * (1.0 - t / dur)
		s[i] = (saw * 0.55 + breath * 0.12) * env
	return _make_wav(s, SAMPLE_RATE)

func _synth_pickup() -> AudioStreamWAV:
	# 880Hz → 1320Hz 两个短促正弦，各自指数衰减
	var n: int = int(SAMPLE_RATE * 0.17)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var v: float = 0.0
		if t < 0.07:
			v = sin(TAU * 880.0 * t) * exp(-t * 32.0)
		else:
			var lt: float = t - 0.07
			v = sin(TAU * 1320.0 * lt) * exp(-lt * 26.0)
		s[i] = v * 0.55
	return _make_wav(s, SAMPLE_RATE)

func _synth_drone() -> AudioStreamWAV:
	# 55Hz + 55.5Hz 差拍（0.5Hz 拍频）+ 110Hz 弱泛音 + 0.25Hz 呼吸
	# 时长取 4s：55×4=220、55.5×4=222、0.25×4=1 均为整数周期 → 循环无缝
	var dur: float = 4.0
	var n: int = int(SAMPLE_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var a: float = sin(TAU * 55.0 * t)
		var b: float = sin(TAU * 55.5 * t)
		var c: float = sin(TAU * 110.0 * t) * 0.16
		var breathe: float = 0.72 + 0.28 * sin(TAU * 0.25 * t)
		s[i] = ((a + b) * 0.30 + c * 0.14) * breathe
	return _make_wav(s, SAMPLE_RATE, true)
