extends SceneTree
## Headless unit tests for TyreModel.
## Run: godot --headless --path . -s res://tests/test_tyre_model.gd

var _failures := 0


func _initialize() -> void:
	var soft: TyreCompound = load("res://data/compounds/soft.tres")
	var medium: TyreCompound = load("res://data/compounds/medium.tres")
	var hard: TyreCompound = load("res://data/compounds/hard.tres")
	_assert(soft != null and medium != null and hard != null, "compounds load")

	# Grip peaks at the optimal temperature.
	var at_opt := TyreModel.grip(soft, 0.0, soft.optimal_temp_c)
	var cold := TyreModel.grip(soft, 0.0, soft.optimal_temp_c - 30.0)
	var hot := TyreModel.grip(soft, 0.0, soft.optimal_temp_c + 30.0)
	_assert(at_opt > cold and at_opt > hot, "grip peaks at optimal temp (%f vs cold %f / hot %f)" % [at_opt, cold, hot])
	_assert(absf(at_opt - soft.base_grip) < 0.001, "peak grip equals base_grip")

	# Fresh soft > fresh medium > fresh hard (each in its own window).
	var g_soft := TyreModel.grip(soft, 0.0, soft.optimal_temp_c)
	var g_med := TyreModel.grip(medium, 0.0, medium.optimal_temp_c)
	var g_hard := TyreModel.grip(hard, 0.0, hard.optimal_temp_c)
	_assert(g_soft > g_med and g_med > g_hard, "compound grip ordering")

	# Grip strictly decreases with wear; cliff makes it fall faster after 65%.
	var prev := TyreModel.grip(soft, 0.0, soft.optimal_temp_c)
	var drop_before_cliff := 0.0
	var drop_after_cliff := 0.0
	for i in range(1, 21):
		var w := i / 20.0
		var g := TyreModel.grip(soft, w, soft.optimal_temp_c)
		_assert(g <= prev + 0.0001, "grip monotonic in wear (w=%f)" % w)
		if w <= 0.65:
			drop_before_cliff = maxf(drop_before_cliff, prev - g)
		else:
			drop_after_cliff = maxf(drop_after_cliff, prev - g)
		prev = g
	_assert(drop_after_cliff > drop_before_cliff * 2.0, "cliff steeper than pre-cliff slope")

	# Overheating raises wear exponentially; management skill reduces it.
	var w_cool := TyreModel.wear_delta(soft, soft.optimal_temp_c, 1.0, 50.0, 50.0, 1.0)
	var w_hot := TyreModel.wear_delta(soft, soft.optimal_temp_c + 20.0, 1.0, 50.0, 50.0, 1.0)
	_assert(w_hot > w_cool * 1.5, "overheating accelerates wear (%f vs %f)" % [w_hot, w_cool])
	var w_managed := TyreModel.wear_delta(soft, soft.optimal_temp_c, 1.0, 100.0, 50.0, 1.0)
	_assert(w_managed < w_cool, "tyre management reduces wear")

	# Temperature converges: heating in corners, cooling toward ambient on straights.
	var t := 70.0
	for i in 400:
		t += TyreModel.temp_delta(i % 2 == 0, t, 24.0, 1.0)
	_assert(t > 60.0 and t < 140.0, "temp equilibrium in sane range (got %f)" % t)

	# No NaN/inf across the whole temp/wear grid.
	for wi in 11:
		for ti in 21:
			var g := TyreModel.grip(soft, wi / 10.0, 20.0 + ti * 10.0)
			_assert(is_finite(g) and g > 0.0, "grip finite at wear=%f temp=%f" % [wi / 10.0, 20.0 + ti * 10.0])

	if _failures == 0:
		print("TYRE MODEL TESTS: ALL PASSED")
		quit(0)
	else:
		print("TYRE MODEL TESTS: %d FAILURES" % _failures)
		quit(1)


func _assert(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: " + label)
