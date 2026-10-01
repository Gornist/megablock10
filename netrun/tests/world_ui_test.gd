extends GdUnitTestSuite


func test_deck_panel_uses_viewport_surface() -> void:
	var d: DeckPanel = auto_free(DeckPanel.new())
	add_child(d)
	d.set_deck({"daemons": [{"id": "x", "name": "Взлом", "cooldown_left": 0.0}], "selected": "x"})
	assert_bool(d.has_viewport_surface()).is_true()
	assert_str(d.row_texts()[1]).is_equal("> Взлом  готово")


func test_trace_indicator_text() -> void:
	var t: TraceIndicator = auto_free(TraceIndicator.new())
	add_child(t)
	t.set_trace(80.0)
	assert_str(t.shown_text()).is_equal("блокировка 80")
