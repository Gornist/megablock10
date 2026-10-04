extends GdUnitTestSuite
## Сглаживание чужих аватаров и ICE (P1): буфер состояний, часы сервера, сборка RemoteTracks. Чистая логика.


func _buf(points: Array) -> StateBuffer:
	var b := StateBuffer.new()
	for e in points:
		b.push(e[0], Vector3(e[1], 0, 0))
	return b


func _x(b: StateBuffer, t: float) -> float:
	return (b.sample(t)["p"] as Vector3).x


func test_empty_buffer_has_no_pose() -> void:
	assert_bool(StateBuffer.new().sample(1.0).is_empty()).is_true()


func test_interpolates_between_two_samples() -> void:
	var b := _buf([[1.0, 0.0], [1.1, 2.0]])
	assert_float(_x(b, 1.05)).is_equal_approx(1.0, 0.0001)
	assert_float(_x(b, 1.0)).is_equal_approx(0.0, 0.0001)
	assert_float(_x(b, 1.1)).is_equal_approx(2.0, 0.0001)


func test_before_first_sample_holds_first() -> void:
	assert_float(_x(_buf([[1.0, 5.0], [1.1, 6.0]]), 0.2)).is_equal_approx(5.0, 0.0001)


func test_lost_packet_interpolates_across_longer_span() -> void:
	# пакет на t=1.1 потерян: идём прямо от 1.0 к 1.2
	var b := _buf([[1.0, 0.0], [1.2, 2.0]])
	assert_float(_x(b, 1.1)).is_equal_approx(1.0, 0.0001)


func test_reordered_packet_lands_in_its_place() -> void:
	var b := _buf([[1.0, 0.0], [1.2, 2.0]])
	assert_bool(b.push(1.1, Vector3(1.0, 0, 0))).is_true()  # опоздавший
	assert_int(b.size()).is_equal(3)
	assert_float(_x(b, 1.05)).is_equal_approx(0.5, 0.0001)
	assert_float(_x(b, 1.15)).is_equal_approx(1.5, 0.0001)


func test_duplicate_time_replaces() -> void:
	var b := _buf([[1.0, 0.0]])
	b.push(1.0, Vector3(7, 0, 0))
	assert_int(b.size()).is_equal(1)
	assert_float(_x(b, 1.0)).is_equal_approx(7.0, 0.0001)


func test_extrapolates_briefly_then_holds() -> void:
	var b := _buf([[1.0, 0.0], [1.1, 1.0]])  # скорость 10 м/с
	assert_float(_x(b, 1.15)).is_equal_approx(1.5, 0.0001)
	# дальше MAX_EXTRAPOLATE не едем: стоим на 1.0 + 10 * 0.1
	assert_float(_x(b, 5.0)).is_equal_approx(2.0, 0.0001)


func test_big_gap_does_not_slide() -> void:
	var b := _buf([[1.0, 0.0], [4.0, 30.0]])  # три секунды тишины
	assert_float(_x(b, 2.5)).is_equal_approx(0.0, 0.0001)
	assert_float(_x(b, 4.0)).is_equal_approx(30.0, 0.0001)


func test_server_clock_going_back_resets_buffer() -> void:
	var b := _buf([[100.0, 1.0], [100.1, 2.0]])
	b.push(0.5, Vector3(9, 0, 0))  # сервер перезапустили, время пошло с нуля
	assert_int(b.size()).is_equal(1)
	assert_float(_x(b, 0.5)).is_equal_approx(9.0, 0.0001)


func test_small_late_packet_is_not_a_reset() -> void:
	var b := _buf([[10.0, 0.0], [10.1, 1.0]])
	b.push(9.5, Vector3(-1, 0, 0))  # сильно опоздал, но не на REWIND_RESET: просто в начало
	assert_int(b.size()).is_equal(3)


func test_full_buffer_drops_older_than_oldest() -> void:
	var b := StateBuffer.new()
	for i in StateBuffer.MAX_SAMPLES:
		b.push(10.0 + i * 0.05, Vector3.ZERO)
	assert_bool(b.push(9.5, Vector3.ZERO)).is_false()
	assert_int(b.size()).is_equal(StateBuffer.MAX_SAMPLES)


func test_buffer_size_is_bounded() -> void:
	var b := StateBuffer.new()
	for i in 200:
		b.push(i * 0.05, Vector3.ZERO)
	assert_int(b.size()).is_equal(StateBuffer.MAX_SAMPLES)


func test_yaw_takes_short_way_round() -> void:
	var b := StateBuffer.new()
	b.push(0.0, Vector3.ZERO, deg_to_rad(170.0))
	b.push(1.0, Vector3.ZERO, deg_to_rad(-170.0))
	var yaw: float = b.sample(0.5)["yaw"]
	assert_float(absf(wrapf(yaw, -PI, PI))).is_equal_approx(PI, 0.001)


# --- ServerClock ---

func test_clock_takes_fastest_packet_as_reference() -> void:
	var c := ServerClock.new()
	c.observe(10.0, 110.05)  # путь 0.05
	c.observe(10.1, 110.30)  # путь 0.20: «позже»
	c.observe(10.2, 110.25)
	assert_float(c.offset()).is_equal_approx(100.05, 0.0001)
	assert_float(c.render_time(120.0, 0.1)).is_equal_approx(19.85, 0.0001)


func test_clock_jump_resets_at_once() -> void:
	var c := ServerClock.new()
	for i in 10:
		c.observe(10.0 + i * 0.05, 110.0 + i * 0.05)
	c.observe(0.1, 111.0)  # сервер перезапущен: серверное время ушло в ноль
	assert_float(c.offset()).is_equal_approx(110.9, 0.0001)


func test_clock_window_forgets_old_minimum() -> void:
	var c := ServerClock.new()
	c.observe(0.0, 100.0)  # смещение 100
	for i in ServerClock.WINDOW:
		c.observe(0.1 + i * 0.1, 100.4 + i * 0.1)  # теперь путь стабильно на 0.4 дольше
	assert_float(c.offset()).is_equal_approx(100.3, 0.0001)


# --- RemoteTracks ---

func test_tracks_smooth_avatar_with_delay_and_jitter() -> void:
	var tr := RemoteTracks.new()
	# аватар едет со скоростью 2 м/с, пакеты каждые 0.05 с, дрожь доставки до 40 мс
	var jitter := [0.0, 0.04, 0.01, 0.03, 0.0, 0.02]
	for i in 40:
		var k := i * 0.05
		tr.on_avatars({"k": k, "a": [[3, 2.0 * k, 0.0]]}, k + 0.02 + jitter[i % 6])
	var now := 40 * 0.05 + 0.02
	var pose := tr.avatar_pose("3", now)
	# показываем на AVATAR_DELAY позже реального положения (+ задержка путей минимума): отстаём не больше ~0.2 м
	var truth := 2.0 * (now - 0.02)
	var err := truth - (pose["p"] as Vector3).x
	assert_float(err).is_between(0.0, 0.4)


func test_tracks_remove_avatar_missing_from_list() -> void:
	var tr := RemoteTracks.new()
	tr.on_avatars({"k": 1.0, "a": [[1, 0.0, 0.0], [2, 1.0, 1.0]]}, 1.0)
	var gone := tr.on_avatars({"k": 1.05, "a": [[2, 1.0, 1.0]]}, 1.05)
	assert_array(gone).is_equal(["1"])
	assert_bool(tr.avatar_pose("1", 1.1).is_empty()).is_true()
	assert_bool(tr.avatar_pose("2", 1.1).is_empty()).is_false()


func test_tracks_ice_from_state_with_facing() -> void:
	var tr := RemoteTracks.new()
	tr.on_state({"k": 1.0, "ice": [{"id": "ice_1", "p": [1.0, 0.0, -6.0], "f": [0.0, -1.0], "s": 0}]}, 1.0)
	var pose := tr.ice_pose("ice_1", 5.0)
	assert_vector(pose["p"]).is_equal(Vector3(1.0, 0.0, -6.0))
	assert_float(pose["yaw"]).is_equal_approx(0.0, 0.0001)


# ---------------------------------------------------------------- скачок (телепорт чужого аватара)

func _jump_buf() -> StateBuffer:
	var b := StateBuffer.new()
	b.push(1.00, Vector3(0.0, 0, 0), 0.0, 0)
	b.push(1.05, Vector3(0.1, 0, 0), 0.0, 0)
	b.push(1.10, Vector3(4.1, 0, 0), 0.0, 1)   # телепорт: счётчик скачков вырос
	b.push(1.15, Vector3(4.2, 0, 0), 0.0, 1)
	return b


func test_jump_is_not_interpolated_across() -> void:
	var b := _jump_buf()
	assert_float(_x(b, 1.02)).is_equal_approx(0.04, 0.0001)    # до скачка — гладко
	assert_float(_x(b, 1.07)).is_equal_approx(0.1, 0.0001)     # между снимками до/после скачка стоим на старом месте
	assert_float(_x(b, 1.099)).is_equal_approx(0.1, 0.0001)
	assert_float(_x(b, 1.10)).is_equal_approx(4.1, 0.0001)     # и прыгаем, когда время дошло
	assert_float(_x(b, 1.125)).is_equal_approx(4.15, 0.0001)   # после — снова гладко


func test_no_extrapolation_from_a_jump() -> void:
	var b := StateBuffer.new()
	b.push(1.00, Vector3(0, 0, 0), 0.0, 0)
	b.push(1.05, Vector3(4, 0, 0), 0.0, 1)
	assert_float(_x(b, 1.10)).is_equal_approx(4.0, 0.0001)     # скорость 80 м/с из пары до/после скачка не выдумываем


func test_jump_survives_lost_packets() -> void:
	# Пакеты между 1.00 и 1.30 потеряны: счётчик в каждом пакете, поэтому скачок всё равно виден, а не растягивается в «ползущий» путь.
	var b := StateBuffer.new()
	b.push(1.00, Vector3(0, 0, 0), 0.0, 3)
	b.push(1.30, Vector3(4, 0, 0), 0.0, 4)
	assert_float(_x(b, 1.15)).is_equal_approx(0.0, 0.0001)
	assert_float(_x(b, 1.30)).is_equal_approx(4.0, 0.0001)


func test_default_jump_counter_keeps_old_behaviour() -> void:
	var b := _buf([[1.0, 0.0], [1.1, 2.0]])
	assert_float(_x(b, 1.05)).is_equal_approx(1.0, 0.0001)


func test_remote_tracks_reads_jump_counter_from_avatar_entries() -> void:
	var rt := RemoteTracks.new()
	rt.on_avatars({"k": 1.00, "a": [[5, 0.0, 0.0]]}, 1.00)
	rt.on_avatars({"k": 1.05, "a": [[5, 0.1, 0.0]]}, 1.05)
	rt.on_avatars({"k": 1.10, "a": [[5, 4.1, 0.0, 1]]}, 1.10)
	rt.on_avatars({"k": 1.15, "a": [[5, 4.2, 0.0, 1]]}, 1.15)
	var b: StateBuffer = rt.avatars["5"]
	assert_float((b.sample(1.07)["p"] as Vector3).x).is_equal_approx(0.1, 0.0001)
	assert_float((b.sample(1.125)["p"] as Vector3).x).is_equal_approx(4.15, 0.0001)
