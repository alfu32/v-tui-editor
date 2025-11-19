module editor

fn test_insert_and_navigation() {
	mut buf := new_text_buffer()
	buf.insert_text('hello world')
	assert buf.lines.len == 1
	assert buf.lines[0] == 'hello world'
	buf.move_left(false, true)
	assert buf.cursor.column == 6
	buf.move_left(true, false)
	assert buf.has_selection()
	buf.copy_selection()
	assert buf.clipboard == ' '
}

fn test_newlines_and_selection() {
	mut buf := new_text_buffer()
	buf.insert_text('one\ntwo\nthree')
	assert buf.lines.len == 3
	buf.move_start_of_line(false)
	buf.move_up(false)
	assert buf.cursor.line == 1
	buf.move_end_of_line(false)
	buf.move_left(true, false)
	assert buf.has_selection()
	buf.cut_selection()
	assert buf.clipboard.len > 0
}

fn test_viewport_slice_marks_cursor_and_selection() {
	mut buf := new_text_buffer()
	buf.load_text('alpha\nbeta\ngamma')
	buf.start_selection(Position{ line: 1, column: 1 })
	buf.select_to(Position{ line: 1, column: 4 })
	view := EditorViewport{
		x:      0
		y:      0
		width:  8
		height: 3
	}
	slice := buf.viewport_slice(view)
	assert slice.lines.len == 3
	assert slice.lines[1].gutter == '     2  '
	mut has_selected := false
	for seg in slice.lines[1].segments {
		if seg.selected {
			has_selected = true
		}
	}
	assert has_selected
	assert slice.cursor != none
	cursor := slice.cursor or { CursorView{} }
	assert cursor.line == 1
	assert cursor.column == 4
}

fn test_viewport_slice_respects_offsets() {
	mut buf := new_text_buffer()
	buf.load_text('0123456789\nabcdefghij')
	view := EditorViewport{
		x:      4
		y:      1
		width:  4
		height: 1
	}
	slice := buf.viewport_slice(view)
	assert slice.lines.len == 1
	assert slice.lines[0].line_index == 1
	assert slice.lines[0].segments.len == 1
	assert slice.lines[0].segments[0].text == 'efgh'
}
