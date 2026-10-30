extends GdUnitTestSuite
## Основания препятствий для облака (NodeView._obstacle_rects → AssetMaterials.set_cloud_occluders): по прямоугольнику на блок «#» — вокруг них пол растушёвывается.


func _layout() -> LayoutData:
	var rows := ["S#1#####", "########", "########", "########", "########", "########", "########", "#######E"]
	var ld := LayoutData.parse({"name": "pillars", "cells": rows, "vaults": [], "ice": []})
	assert_str(ld.error).is_empty()
	return ld


func test_прямоугольник_на_каждый_блок_препятствия_размером_с_блок() -> void:
	var ld := _layout()
	var view := NodeView.new()
	add_child(view)
	view.set_look("BASE", ld)
	var rects := view._obstacle_rects()
	var blocks := 0
	for line: String in ld.blocks:
		blocks += line.count("#")
	assert_int(rects.size()).is_equal(blocks)
	for r in rects:
		assert_float(r.size.x).is_equal(NodeLayout.CELL)
		assert_float(r.size.y).is_equal(NodeLayout.CELL)
	var c := NodeLayout.cell_center(1, 0)   # блок «#» рядом со входом
	var found := false
	for r in rects:
		if is_equal_approx(r.position.x, c.x - NodeLayout.CELL * 0.5) and is_equal_approx(r.position.y, c.z - NodeLayout.CELL * 0.5):
			found = true
	assert_bool(found).is_true()
	view.free()


func test_без_раскладки_оснований_нет() -> void:
	var view := auto_free(NodeView.new()) as NodeView
	assert_int(view._obstacle_rects().size()).is_equal(0)
