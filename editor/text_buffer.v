module editor

pub const default_gutter_width = 6

pub struct Position {
pub mut:
	line   int
	column int
}

pub struct SelectionRange {
pub:
	start Position
	end   Position
}

pub enum NotificationKind {
	copy
	cut
}

pub struct Notification {
pub:
	kind NotificationKind
	text string
}

pub struct EditorViewport {
pub:
	x      int
	y      int
	width  int
	height int
}

pub struct ViewSegment {
pub:
	text     string
	selected bool
	cursor   bool
}

pub struct ViewLine {
pub:
	line_index int
	gutter     string
	segments   []ViewSegment
}

pub struct ViewportSlice {
pub:
	lines      []ViewLine
	total_lines int
}

pub struct TextBuffer {
pub mut:
	lines        []string
	cursor       Position
	anchor       ?Position
	clipboard    string
	notifications []Notification
}

pub fn new_text_buffer() &TextBuffer {
	return &TextBuffer{
		lines: ['']
		cursor: Position{}
	}
}

pub fn (mut b TextBuffer) load_text(text string) {
	mut normalized := text.replace('\r\n', '\n')
	if normalized.len == 0 {
		b.lines = ['']
	} else {
		b.lines = normalized.split_into_lines()
		if normalized.ends_with('\n') {
			b.lines << ''
		}
	}
	b.cursor = Position{}
	b.anchor = none
}

pub fn (b &TextBuffer) clone() TextBuffer {
	return TextBuffer{
		lines: b.lines.clone()
		cursor: Position{ b.cursor.line, b.cursor.column }
		anchor: b.anchor
		clipboard: b.clipboard
	}
}

pub fn (mut b TextBuffer) insert_text(text string) {
	if text.len == 0 {
		return
	}
	b.delete_selection()
	mut parts := text.replace('\r\n', '\n').split('\n')
	mut current := b.current_line()
	mut prefix := current[..b.cursor.column]
	mut suffix := current[b.cursor.column..]
	if parts.len == 1 {
		new_line := prefix + parts[0] + suffix
		b.lines[b.cursor.line] = new_line
		b.cursor.column += parts[0].len
		return
	}
	first := prefix + parts[0]
	last := parts[parts.len - 1] + suffix
	b.lines[b.cursor.line] = first
	mut insert_index := b.cursor.line + 1
	for part in parts[1..parts.len - 1] {
		b.lines.insert(insert_index, part)
		insert_index++
	}
	b.lines.insert(insert_index, last)
	b.cursor.line = insert_index
	b.cursor.column = parts[parts.len - 1].len
}

pub fn (mut b TextBuffer) insert_newline() {
	b.insert_text('\n')
}

pub fn (mut b TextBuffer) move_left(expand bool, word bool) {
	mut pos := b.cursor
	if word {
		pos = b.word_boundary_left()
	} else if pos.column > 0 {
		pos.column--
	} else if pos.line > 0 {
		pos.line--
		pos.column = b.lines[pos.line].len
	}
	b.move_cursor_to(pos, expand)
}

pub fn (mut b TextBuffer) move_right(expand bool, word bool) {
	mut pos := b.cursor
	line := b.lines[pos.line]
	if word {
		pos = b.word_boundary_right()
	} else if pos.column < line.len {
		pos.column++
	} else if pos.line < b.lines.len - 1 {
		pos.line++
		pos.column = 0
	}
	b.move_cursor_to(pos, expand)
}

pub fn (mut b TextBuffer) move_up(expand bool) {
	if b.cursor.line == 0 {
		b.move_cursor_to(Position{0,0}, expand)
		return
	}
	mut pos := Position{
		line: b.cursor.line - 1
		column: b.cursor.column
	}
	line_len := b.lines[pos.line].len
	if pos.column > line_len {
		pos.column = line_len
	}
	b.move_cursor_to(pos, expand)
}

pub fn (mut b TextBuffer) move_down(expand bool) {
	if b.cursor.line >= b.lines.len - 1 {
		pos := Position{ b.lines.len - 1, b.lines[b.lines.len - 1].len }
		b.move_cursor_to(pos, expand)
		return
	}
	mut pos := Position{
		line: b.cursor.line + 1
		column: b.cursor.column
	}
	line_len := b.lines[pos.line].len
	if pos.column > line_len {
		pos.column = line_len
	}
	b.move_cursor_to(pos, expand)
}

pub fn (mut b TextBuffer) move_start_of_line(expand bool) {
	b.move_cursor_to(Position{ b.cursor.line, 0 }, expand)
}

pub fn (mut b TextBuffer) move_end_of_line(expand bool) {
	b.move_cursor_to(Position{ b.cursor.line, b.lines[b.cursor.line].len }, expand)
}

pub fn (mut b TextBuffer) select_all() {
	last_line := b.lines.len - 1
	last_col := b.lines[last_line].len
	b.anchor = Position{0,0}
	b.cursor = Position{last_line, last_col}
}

pub fn (mut b TextBuffer) delete_backspace() {
	if b.delete_selection() {
		return
	}
	if b.cursor.column > 0 {
		mut line := b.current_line()
		line = line[..b.cursor.column - 1] + line[b.cursor.column..]
		b.lines[b.cursor.line] = line
		b.cursor.column--
		return
	}
	if b.cursor.line == 0 {
		return
	}
	prev_line := b.lines[b.cursor.line - 1]
	current_line := b.lines[b.cursor.line]
	new_line := prev_line + current_line
	b.lines[b.cursor.line - 1] = new_line
	b.lines.delete(b.cursor.line)
	b.cursor.line--
	b.cursor.column = prev_line.len
}

pub fn (mut b TextBuffer) delete_forward() {
	if b.delete_selection() {
		return
	}
	mut line := b.current_line()
	if b.cursor.column < line.len {
		line = line[..b.cursor.column] + line[b.cursor.column + 1..]
		b.lines[b.cursor.line] = line
		return
	}
	if b.cursor.line >= b.lines.len - 1 {
		return
	}
	line = line + b.lines[b.cursor.line + 1]
	b.lines[b.cursor.line] = line
	b.lines.delete(b.cursor.line + 1)
}

pub fn (mut b TextBuffer) copy_selection() bool {
	if selection := b.selection_range() {
		b.clipboard = b.extract_text(selection)
		b.notifications << Notification{ kind: .copy, text: b.clipboard }
		return true
	}
	return false
}

pub fn (mut b TextBuffer) cut_selection() bool {
	if selection := b.selection_range() {
		b.clipboard = b.extract_text(selection)
		b.delete_selection()
		b.notifications << Notification{ kind: .cut, text: b.clipboard }
		return true
	}
	return false
}

pub fn (mut b TextBuffer) paste_clipboard() {
	if b.clipboard.len == 0 {
		return
	}
	b.insert_text(b.clipboard)
}

pub fn (mut b TextBuffer) consume_notifications() []Notification {
	mut out := b.notifications.clone()
	b.notifications.clear()
	return out
}

pub fn (mut b TextBuffer) start_selection(pos Position) {
	b.cursor = b.clamp_position(pos)
	b.anchor = b.cursor
}

pub fn (mut b TextBuffer) select_to(pos Position) {
	if b.anchor == none {
		b.anchor = b.cursor
	}
	b.cursor = b.clamp_position(pos)
}

pub fn (b TextBuffer) has_selection() bool {
	if anchor := b.anchor {
		return anchor.line != b.cursor.line || anchor.column != b.cursor.column
	}
	return false
}

pub fn (mut b TextBuffer) clear_selection() {
	b.anchor = none
}

pub fn (b TextBuffer) viewport_slice(view EditorViewport) ViewportSlice {
	mut lines := []ViewLine{}
	height := if view.height <= 0 { 1 } else { view.height }
	total := b.lines.len
	for row in 0 .. height {
		line_idx := view.y + row
		if line_idx >= total {
			break
		}
		segments := b.build_segments(line_idx, view.x, view.width)
		gutter := b.gutter_text(line_idx)
		lines << ViewLine{
			line_index: line_idx
			gutter: gutter
			segments: segments
		}
	}
	return ViewportSlice{
		lines: lines
		total_lines: total
	}
}

fn append_segment(mut segments []ViewSegment, text string, selected bool) {
	if text.len == 0 {
		return
	}
	segments << ViewSegment{
		text: text
		selected: selected
	}
}

fn (b TextBuffer) build_segments(line_idx int, view_x int, view_width int) []ViewSegment {
	mut width := view_width
	if width <= 0 {
		width = 1
	}
	line := b.lines[line_idx]
	runes := line.runes()
	selection := b.selection_columns(line_idx)
	caret_line := line_idx == b.cursor.line
	caret_col := b.cursor.column
	mut segments := []ViewSegment{}
	mut current_text := ''
	mut current_selected := false
	mut has_segment := false
	for rel_col in 0 .. width {
		actual_col := view_x + rel_col
		if caret_line && caret_col == actual_col {
			if has_segment {
				append_segment(mut segments, current_text, current_selected)
				current_text = ''
				has_segment = false
			}
			segments << ViewSegment{
				text: '▏'
				cursor: true
			}
		}
		mut ch := ' '
		if actual_col < runes.len {
			ch = runes[actual_col].str()
		}
		selected := selection.intersects(actual_col)
		if !has_segment {
			has_segment = true
			current_selected = selected
			current_text = ch
			continue
		}
		if selected != current_selected {
			append_segment(mut segments, current_text, current_selected)
			current_text = ch
			current_selected = selected
			continue
		}
		current_text += ch
	}
	if has_segment {
		append_segment(mut segments, current_text, current_selected)
	}
	if caret_line && caret_col == view_x + width {
		segments << ViewSegment{
			text: '▏'
			cursor: true
		}
	}
	return segments
}

fn (b TextBuffer) selection_columns(line_idx int) SelectionColumns {
	if selection := b.selection_range() {
		if line_idx < selection.start.line || line_idx > selection.end.line {
			return SelectionColumns{}
		}
		mut start := 0
		mut end := b.lines[line_idx].len
		if line_idx == selection.start.line {
			start = selection.start.column
		}
		if line_idx == selection.end.line {
			end = selection.end.column
		}
		if end < start {
			end = start
		}
		return SelectionColumns{
			start: start
			end: end
			split: true
		}
	}
	return SelectionColumns{}
}

struct SelectionColumns {
	start int
	end   int
	split bool
}

fn (sc SelectionColumns) intersects(column int) bool {
	if !sc.split {
		return false
	}
	return column >= sc.start && column < sc.end
}

fn (b TextBuffer) gutter_text(line_idx int) string {
	line_number := line_idx + 1
	mut num := line_number.str()
	if num.len > default_gutter_width {
		num = num[num.len - default_gutter_width..]
	} else if num.len < default_gutter_width {
		num = ' '.repeat(default_gutter_width - num.len) + num
	}
	return '│${num}│ '
}

fn (mut b TextBuffer) move_cursor_to(pos Position, expand bool) {
	mut new_pos := b.clamp_position(pos)
	if expand {
		if b.anchor == none {
			b.anchor = b.cursor
		}
	} else {
		b.anchor = none
	}
	b.cursor = new_pos
}

fn (b TextBuffer) clamp_position(pos Position) Position {
	mut line := pos.line
	if line < 0 {
		line = 0
	}
	if line >= b.lines.len {
		line = b.lines.len - 1
	}
	mut column := pos.column
	line_len := b.lines[line].len
	if column < 0 {
		column = 0
	}
	if column > line_len {
		column = line_len
	}
	return Position{ line, column }
}

fn (mut b TextBuffer) delete_selection() bool {
	if selection := b.selection_range() {
		text := b.extract_text(selection)
		_ = text
		b.remove_text(selection)
		return true
	}
	return false
}

fn (mut b TextBuffer) remove_text(selection SelectionRange) {
	if selection.start.line == selection.end.line {
		line := b.lines[selection.start.line]
		new_line := line[..selection.start.column] + line[selection.end.column..]
		b.lines[selection.start.line] = new_line
		b.cursor = selection.start
		b.anchor = none
		return
	}
	mut first := b.lines[selection.start.line]
	mut last := b.lines[selection.end.line]
	first = first[..selection.start.column]
	last = last[selection.end.column..]
	b.lines[selection.start.line] = first + last
	for _ in selection.start.line + 1 .. selection.end.line + 1 {
		b.lines.delete(selection.start.line + 1)
	}
	b.cursor = selection.start
	b.anchor = none
}

fn (b TextBuffer) extract_text(selection SelectionRange) string {
	if selection.start.line == selection.end.line {
		line := b.lines[selection.start.line]
		return line[selection.start.column..selection.end.column]
	}
	mut parts := []string{}
	first := b.lines[selection.start.line]
	parts << first[selection.start.column..]
	for i := selection.start.line + 1; i < selection.end.line; i++ {
		parts << b.lines[i]
	}
	last := b.lines[selection.end.line]
	parts << last[..selection.end.column]
	return parts.join('\n')
}

fn (b TextBuffer) selection_range() ?SelectionRange {
	anchor := b.anchor or { return none }
	if anchor.line == b.cursor.line && anchor.column == b.cursor.column {
		return none
	}
	mut start := anchor
	mut end := b.cursor
	if start.line > end.line || (start.line == end.line && start.column > end.column) {
		start, end = end, start
	}
	return SelectionRange{ start, end }
}

fn (b TextBuffer) current_line() string {
	return b.lines[b.cursor.line]
}

fn is_word_char(ch rune) bool {
	return (ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_` || ch == `$`
}

fn (b TextBuffer) word_boundary_left() Position {
	mut pos := b.cursor
	if pos.column == 0 && pos.line == 0 {
		return pos
	}
	mut line_idx := pos.line
	mut column := pos.column
	mut runes := b.lines[line_idx].runes()
	if column == 0 {
		line_idx--
		runes = b.lines[line_idx].runes()
		column = runes.len
	}
	mut i := column - 1
	for i > 0 && !is_word_char(runes[i]) {
		i--
	}
	for i > 0 && is_word_char(runes[i - 1]) {
		i--
	}
	return Position{ line_idx, i }
}

fn (b TextBuffer) word_boundary_right() Position {
	mut pos := b.cursor
	mut line_idx := pos.line
	mut runes := b.lines[line_idx].runes()
	mut column := pos.column
	if column >= runes.len {
		if line_idx < b.lines.len - 1 {
			return Position{ line_idx + 1, 0 }
		}
		return Position{ line_idx, runes.len }
	}
	mut i := column
	for i < runes.len && !is_word_char(runes[i]) {
		i++
	}
	for i < runes.len && is_word_char(runes[i]) {
		i++
	}
	return Position{ line_idx, i }
}
