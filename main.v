import os
import reactive
import strings
import term.ui as tui
import editor

const top_bar_height = 3
const status_bar_height = 2
const divider_width = 1
const min_left_width = 12
const min_right_width = 20
const editor_gutter_chars = editor.default_gutter_width + 3
const editor_bg_color = reactive.TermColor{16, 20, 28}
const editor_fg_color = reactive.TermColor{210, 210, 210}
const editor_cursor_bg = reactive.TermColor{210, 210, 210}
const editor_cursor_fg = reactive.TermColor{20, 24, 32}
const editor_selection_bg = reactive.TermColor{60, 80, 120}
const editor_selection_fg = reactive.TermColor{255, 255, 255}

fn escape_text(value string) string {
	return value
		.replace("&", "&amp;")
		.replace("<", "&lt;")
		.replace(">", "&gt;")
		.replace("\"", "&quot;")
		.replace("'", "&#39;")
}

fn itos(value int) string {
	return "${value}"
}

struct LayoutState {
mut:
	left_panel_width int = 26
	resizing         bool
	viewport_width   int = 80
	viewport_height  int = 24
	tree             &FileTree = unsafe { nil }
	file_entries     []FileTreeEntry
	selected_file    string
	buffer           &editor.TextBuffer = unsafe { nil }
	editor_view_x    int
	editor_view_y    int
	editor_focused   bool
	editor_dragging  bool
	editor_rect      reactive.TermRect
	open_files       []string
	open_panel_height int = 8
	resizing_left_split bool
	mouse_x          int
	mouse_y          int
	hover_tag        string
}

fn clamp_left_width(width int, viewport_width int) int {
	mut min_total := min_left_width + min_right_width + divider_width
	if min_total >= viewport_width {
		return min_left_width
	}
	mut clamped := width
	if clamped < min_left_width {
		clamped = min_left_width
	}
	max_width := viewport_width - min_right_width - divider_width
	if clamped > max_width {
		clamped = max_width
	}
	return clamped
}

fn update_resize(mut state LayoutState, mut e reactive.UiEvent, force bool) {
	if !state.resizing && !force {
		return
	}
	state.viewport_width = e.renderer.ctx.viewport.width
	state.viewport_height = e.renderer.ctx.viewport.height
	state.left_panel_width = clamp_left_width(e.mouse.x, state.viewport_width)
}

fn update_left_split(mut state LayoutState, mouse_y int, main_top int, panel_height int, min_open int, min_tree int) {
	mut new_height := mouse_y - main_top
	mut max_open := panel_height - min_tree - 1
	if max_open < min_open {
		max_open = min_open
	}
	if new_height < min_open {
		new_height = min_open
	}
	if new_height > max_open {
		new_height = max_open
	}
	state.open_panel_height = new_height
}

fn track_pointer(mut state LayoutState, mut e reactive.UiEvent) {
	state.mouse_x = e.mouse.x
	state.mouse_y = e.mouse.y
	if e.target_tag.len > 0 {
		state.hover_tag = e.target_tag
	}
}

fn read_file_preview(path string) []string {
	content := os.read_bytes(path) or {
		return ["Failed to open ${path}: ${err.msg()}"]
	}
	return (content.bytestr()).split_into_lines()
}

fn add_open_file(mut state LayoutState, path string) {
	if path.len == 0 {
		return
	}
	mut existing_index := -1
	for idx, value in state.open_files {
		if value == path {
			existing_index = idx
			break
		}
	}
	if existing_index == -1 {
		state.open_files.prepend(path)
	} else if existing_index > 0 {
		state.open_files.delete(existing_index)
		state.open_files.prepend(path)
	}
}

fn build_file_list_markup(mut state LayoutState, left_width int, main_height int, mut handlers map[string]reactive.UiEventHandler) string {
	mut b := strings.new_builder(256)
	mut available := main_height - 3
	if available < 1 {
		available = 1
	}
	row_height := 1
	mut row := 0
	for idx, entry in state.file_entries {
		if row >= available {
			break
		}
		line_top := 3 + row * row_height
		mut entry_width := if left_width > 4 { left_width - 4 } else { left_width }
		if entry_width < 1 {
			entry_width = 1
		}
		mut padding_left := 2 + entry.padding * 2
		if padding_left < 2 {
			padding_left = 2
		}
		mut label := escape_text(entry.name)
		if entry.typ == 'folder' {
			mut symbol := '[+]'
			if entry.is_open {
				symbol = '[-]'
			}
			label = '${symbol} ${label}'
		}
		mut fg := '#d0d0d0'
		mut bg := '#1f2736'
		if entry.typ == 'file' && entry.full_path == state.selected_file {
			fg = '#ffffff'
			bg = '#2f3e5c'
		}
		node_tag := 'entry-${idx}'
		entry_copy := entry
		handler_name := 'file_select_${idx}'
		handlers[handler_name] = fn [mut state, entry_copy, node_tag] (mut e reactive.UiEvent) {
			if e.target_tag != node_tag {
				return
			}
			if isnil(state.tree) {
				return
			}
			if entry_copy.typ == 'folder' {
				state.tree.toggle(entry_copy.full_path)
				refresh_file_entries(mut state)
			} else {
				state.selected_file = entry_copy.full_path
				if isnil(state.buffer) {
					state.buffer = editor.new_text_buffer()
				}
				text := os.read_bytes(entry_copy.full_path) or { []u8{} }
				state.buffer.load_text(text.bytestr())
				state.editor_view_y = 0
				state.editor_view_x = 0
				add_open_file(mut state, entry_copy.full_path)
			}
		}
		b.write_string("\n\t\t\t<text tag=\"${node_tag}\" onclick={" + handler_name + "} style=\"top:${line_top};left:${padding_left};width:${entry_width};height:1;fg:${fg};bg:${bg}\">")
		b.write_string(label)
		b.write_string("</text>")
		row++
	}
	if state.file_entries.len == 0 {
		b.write_string("\n\t\t\t<text style=\"top:3;left:2;fg:#888888\">(no files)</text>")
	}
	return b.str()
}

fn truncate_line(line string, limit int) string {
	if limit <= 0 {
		return ""
	}
	if line.len <= limit {
		return line
	}
	return line[..limit]
}

fn editor_background_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_bg_color
		foreground: editor_fg_color
		border: 'empty'
		line: 'empty'
	)
}

fn editor_selection_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_selection_bg
		foreground: editor_selection_fg
		border: 'empty'
		line: 'empty'
	)
}

fn editor_cursor_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_cursor_bg
		foreground: editor_cursor_fg
		border: 'empty'
		line: 'empty'
	)
}

fn refresh_file_entries(mut state LayoutState) {
	if isnil(state.tree) {
		return
	}
	state.file_entries = state.tree.flattened()
}

fn build_editor_view(mut state LayoutState, width int, height int, work_left int, main_top int) reactive.VNode {
	state.editor_rect = reactive.TermRect{
		x: work_left
		y: main_top
		width: width
		height: height
	}
	if isnil(state.buffer) {
		state.buffer = editor.new_text_buffer()
	}
	ensure_cursor_visible(mut state, width, height)
	mut content_width := width - editor_gutter_chars
	if content_width < 1 {
		content_width = 1
	}
	viewport := editor.EditorViewport{
		x: state.editor_view_x
		y: state.editor_view_y
		width: content_width
		height: height
	}
	slice := state.buffer.viewport_slice(viewport)
	mut children := []reactive.VNode{}
	children << reactive.rect(reactive.NodeSpec{
		props: reactive.TermProps{ width: width, height: height }
		style: editor_background_style()
	})
	for idx, line in slice.lines {
		mut left := 0
		children << reactive.text(reactive.NodeSpec{
			tag: 'editor-gutter'
			props: reactive.TermProps{ top: idx, left: left, text: line.gutter }
			style: editor_background_style()
		})
		left += editor_gutter_chars
		for seg in line.segments {
			mut style := editor_background_style()
			if seg.cursor {
				style = editor_cursor_style()
			} else if seg.selected {
				style = editor_selection_style()
			}
			if seg.text.len == 0 {
				continue
			}
			children << reactive.text(reactive.NodeSpec{
				props: reactive.TermProps{ top: idx, left: left, text: seg.text }
				style: style
			})
			left += seg.text.len
		}
	}
	editor_handler := fn [mut state, width, height, work_left, main_top] (mut e reactive.UiEvent) {
		handle_editor_event(mut state, width, height, work_left, main_top, mut e)
	}
	return reactive.relative(reactive.NodeSpec{
		tag: 'code-editor'
		props: reactive.TermProps{ width: width, height: height }
		style: editor_background_style()
		children: children
		events: [editor_handler]
	})
}

fn editor_hit_test(rect reactive.TermRect, x int, y int) bool {
	return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
}

fn handle_editor_event(mut state LayoutState, width int, height int, work_left int, main_top int, mut e reactive.UiEvent) {
	if isnil(state.buffer) {
		return
	}
	if e.kind == .mouse_down {
		if editor_hit_test(state.editor_rect, e.mouse.x, e.mouse.y) {
			state.editor_focused = true
			pos := editor_position_from_mouse(state, e.mouse.x, e.mouse.y)
			state.buffer.start_selection(pos)
			state.editor_dragging = e.mouse.buttons.left
			ensure_cursor_visible(mut state, width, height)
		} else {
			state.editor_focused = false
		}
		return
	}
	if e.kind == .mouse_move {
		if e.mouse.wheel != 0 && editor_hit_test(state.editor_rect, e.mouse.x, e.mouse.y) {
			state.editor_view_y -= e.mouse.wheel
			mut max_line := state.buffer.lines.len - height
			if max_line < 0 {
				max_line = 0
			}
			if state.editor_view_y < 0 {
				state.editor_view_y = 0
			}
			if state.editor_view_y > max_line {
				state.editor_view_y = max_line
			}
		}
		if state.editor_dragging && e.mouse.buttons.left {
			pos := editor_position_from_mouse(state, e.mouse.x, e.mouse.y)
			state.buffer.select_to(pos)
			ensure_cursor_visible(mut state, width, height)
		} else if state.editor_dragging && !e.mouse.buttons.left {
			state.editor_dragging = false
		}
		return
	}
	if e.kind == .mouse_up {
		if state.editor_dragging {
			state.editor_dragging = false
		}
		return
	}
	if e.kind == .key_down && state.editor_focused {
		handle_editor_key(mut state, width, height, mut e)
	}
}

fn handle_editor_key(mut state LayoutState, width int, height int, mut e reactive.UiEvent) {
	if isnil(state.buffer) {
		return
	}
	mut handled := false
	ctrl := e.key.ctrl
	shift := e.key.shift
	code := int(e.key.code)
	match code {
		int(tui.KeyCode.left) {
			state.buffer.move_left(shift, ctrl)
			handled = true
		}
		int(tui.KeyCode.right) {
			state.buffer.move_right(shift, ctrl)
			handled = true
		}
		int(tui.KeyCode.up) {
			state.buffer.move_up(shift)
			handled = true
		}
		int(tui.KeyCode.down) {
			state.buffer.move_down(shift)
			handled = true
		}
		int(tui.KeyCode.home) {
			state.buffer.move_start_of_line(shift)
			handled = true
		}
		int(tui.KeyCode.end) {
			state.buffer.move_end_of_line(shift)
			handled = true
		}
		int(tui.KeyCode.enter) {
			state.buffer.insert_newline()
			handled = true
		}
		int(tui.KeyCode.backspace) {
			state.buffer.delete_backspace()
			handled = true
		}
		int(tui.KeyCode.delete) {
			state.buffer.delete_forward()
			handled = true
		}
		else {}
	}
	if ctrl {
		match code {
			int(tui.KeyCode.c) {
				state.buffer.copy_selection()
				handled = true
			}
			int(tui.KeyCode.x) {
				state.buffer.cut_selection()
				handled = true
			}
			int(tui.KeyCode.v) {
				state.buffer.paste_clipboard()
				handled = true
			}
			int(tui.KeyCode.a) {
				state.buffer.select_all()
				handled = true
			}
			else {}
		}
	}
	if !handled && !ctrl && !e.key.alt {
		mut ch := e.key.char.str()
		if ch.len > 0 && ch[0] >= 32 {
			state.buffer.insert_text(ch)
			handled = true
		}
	}
	if handled {
		ensure_cursor_visible(mut state, width, height)
	}
}

fn editor_position_from_mouse(state LayoutState, mouse_x int, mouse_y int) editor.Position {
	mut line := mouse_y - state.editor_rect.y + state.editor_view_y
	if line < 0 {
		line = 0
	}
	if line >= state.buffer.lines.len {
		line = state.buffer.lines.len - 1
		if line < 0 {
			line = 0
		}
	}
	mut column := mouse_x - state.editor_rect.x - editor_gutter_chars + state.editor_view_x
	if column < 0 {
		column = 0
	}
	line_len := state.buffer.lines[line].len
	if column > line_len {
		column = line_len
	}
	return editor.Position{ line, column }
}

fn ensure_cursor_visible(mut state LayoutState, width int, height int) {
	mut visible_lines := height
	if visible_lines <= 0 {
		visible_lines = 1
	}
	mut max_line := state.buffer.lines.len - visible_lines
	if max_line < 0 {
		max_line = 0
	}
	if state.buffer.cursor.line < state.editor_view_y {
		state.editor_view_y = state.buffer.cursor.line
	}
	if state.buffer.cursor.line >= state.editor_view_y + visible_lines {
		state.editor_view_y = state.buffer.cursor.line - visible_lines + 1
	}
	if state.editor_view_y < 0 {
		state.editor_view_y = 0
	}
	if state.editor_view_y > max_line {
		state.editor_view_y = max_line
	}
	mut content_width := width - editor_gutter_chars
	if content_width <= 0 {
		content_width = 1
	}
	if state.buffer.cursor.column < state.editor_view_x {
		state.editor_view_x = state.buffer.cursor.column
	}
	if state.buffer.cursor.column >= state.editor_view_x + content_width {
		state.editor_view_x = state.buffer.cursor.column - content_width + 1
	}
	if state.editor_view_x < 0 {
		state.editor_view_x = 0
	}
}

fn open_files_component(mut state LayoutState, width int, height int) reactive.VNode {
	mut b := strings.new_builder(128)
	mut available := if height <= 0 { 1 } else { height }
	for idx, path in state.open_files {
		if idx >= available {
			break
		}
		display := escape_text(os.file_name(path))
		fg := if path == state.selected_file { '#ffffff' } else { '#d0d0d0' }
		bg := if path == state.selected_file { '#2f3e5c' } else { '#1f2736' }
		node_tag := 'open-${idx}'
		handler_name := 'open_click_${idx}'
		mut content_width := width - 4
		if content_width < 1 {
			content_width = width
		}
		b.write_string('\n\t<text tag="${node_tag}" onclick={' + handler_name + '} style="top:${idx + 1};left:2;width:${content_width};height:1;fg:${fg};bg:${bg}">')
		b.write_string(display)
		b.write_string('</text>')
	}
	if state.open_files.len == 0 {
		b.write_string('\n\t<text style="top:1;left:2;fg:#888888">(no open files)</text>')
	}
	template := '<relative tag="open-files" style="width:{{width}};height:{{height}}">' + b.str() + '\n</relative>'
	mut handlers := map[string]reactive.UiEventHandler{}
	for idx, path in state.open_files {
		node_tag := 'open-${idx}'
		handlers['open_click_${idx}'] = fn [mut state, path, node_tag] (mut e reactive.UiEvent) {
			if e.target_tag != node_tag {
				return
			}
			state.selected_file = path
			if isnil(state.buffer) {
				state.buffer = editor.new_text_buffer()
			}
			text := os.read_bytes(path) or { []u8{} }
			state.buffer.load_text(text.bytestr())
			state.editor_view_y = 0
			state.editor_view_x = 0
			add_open_file(mut state, path)
		}
	}
	ctx := reactive.TemplateContext{
		props: {
			'width': itos(width)
			'height': itos(height)
		}
		handlers: handlers
	}
	return reactive.view_from_template(template, ctx) or {
		reactive.text(reactive.NodeSpec{
			tag: 'open-files-error'
			props: reactive.TermProps{ text: 'open files error: ' + err.msg() }
		})
	}
}

fn file_list_component(mut state LayoutState, left_width int, main_height int) reactive.VNode {
	mut local_handlers := map[string]reactive.UiEventHandler{}
	items_markup := build_file_list_markup(mut state, left_width, main_height, mut local_handlers)
	template := r'
<relative tag="file-list" style="width:{{width}};height:{{height}}">
	<text style="top:1;left:2;fg:#9ddcff">Explorer</text>
	@@ITEMS@@
</relative>
'.trim_indent()
	component_template := template.replace('@@ITEMS@@', items_markup)
	ctx := reactive.TemplateContext{
		props: {
			'width': itos(left_width)
			'height': itos(main_height)
		}
		handlers: local_handlers
	}
	return reactive.view_from_template(component_template, ctx) or {
		reactive.text(reactive.NodeSpec{
			tag: 'file-list-error'
			props: reactive.TermProps{ text: 'file list error: ' + err.msg() }
		})
	}
}


const layout_template = r'
<relative tag="root" style="width:{{viewport_width}};height:{{viewport_height}};bg:#181c20" onmousemove={resize_tracker} onmouseup={stop_resize}>
	<rect tag="top-bar" style="width:{{viewport_width}};height:{{top_bar_height}};bg:#2b344d">
		<text style="top:1;left:2;fg:#f0f0f0">V Reactive Workspace</text>
	</rect>
	<rect tag="status-bar" style="top:{{status_top}};width:{{viewport_width}};height:{{status_height}};bg:#222730">
		<text style="top:1;left:2;fg:#c0c0c0">{{status_text}}</text>
	</rect>
	<relative tag="main" style="top:{{main_top}};width:{{viewport_width}};height:{{main_height}}">
		<rect tag="left-panel" style="width:{{left_width}};height:{{main_height}};bg:#1f2736;fg:#f0f0f0">
			<relative tag="left-open" style="width:{{left_width}};height:{{open_panel_height}}">
				<slot name="open_files"/>
			</relative>
			<rect tag="left-split-divider" style="top:{{open_panel_height}};width:{{left_width}};height:1;bg:#4a5368" onmousedown={start_split_resize} />
			<relative tag="left-tree" style="top:{{open_panel_height_plus_one}};width:{{left_width}};height:{{tree_panel_height}}">
				<slot name="file_tree"/>
			</relative>
		</rect>
		<rect tag="divider" style="left:{{divider_left}};width:{{divider_width}};height:{{main_height}};bg:#4a5368" onmousedown={start_resize} />
		<rect tag="work" style="left:{{work_left}};width:{{work_width}};height:{{main_height}};bg:#101820">
			<slot name="work_panel"/>
		</rect>
	</relative>
</relative>
'.trim_indent()


fn build_layout_view(mut state LayoutState) reactive.VNode {
	viewport_width := state.viewport_width
	viewport_height := state.viewport_height
	mut status_top := viewport_height - status_bar_height
	if status_top < top_bar_height {
		status_top = top_bar_height
	}
	main_height := if viewport_height > top_bar_height + status_bar_height {
		viewport_height - top_bar_height - status_bar_height
	} else {
		1
	}
	state.left_panel_width = clamp_left_width(state.left_panel_width, viewport_width)
	left_width := state.left_panel_width
	work_left := left_width + divider_width
	mut work_width := viewport_width - work_left
	if work_width < min_right_width {
		work_width = min_right_width
	}
	left_panel_height := main_height
	min_open := 3
	min_tree := 4
	mut open_panel_height := state.open_panel_height
	mut max_open := left_panel_height - min_tree - 1
	if max_open < min_open {
		max_open = min_open
	}
	if open_panel_height < min_open {
		open_panel_height = min_open
	}
	if open_panel_height > max_open {
		open_panel_height = max_open
	}
	if open_panel_height < min_open {
		open_panel_height = min_open
	}
	state.open_panel_height = open_panel_height
	mut tree_panel_height := left_panel_height - open_panel_height - 1
	if tree_panel_height < min_tree {
		tree_panel_height = min_tree
	}
	main_top := top_bar_height
	mut props := map[string]string{}
	props["viewport_width"] = itos(viewport_width)
	props["viewport_height"] = itos(viewport_height)
	props["top_bar_height"] = itos(top_bar_height)
	props["status_height"] = itos(status_bar_height)
	props["status_top"] = itos(status_top)
	props["main_top"] = itos(top_bar_height)
	props["main_height"] = itos(main_height)
	props["left_width"] = itos(left_width)
	props["divider_left"] = itos(left_width)
	props["divider_width"] = itos(divider_width)
	props["work_left"] = itos(work_left)
	props["work_width"] = itos(work_width)
	props["open_panel_height"] = itos(open_panel_height)
	props["open_panel_height_plus_one"] = itos(open_panel_height + 1)
	props["tree_panel_height"] = itos(tree_panel_height)
	status_hover := if state.hover_tag.len > 0 { state.hover_tag } else { "none" }
	status_line := "Panel ${left_width}px | Editor ${work_width}px | Mouse ${state.mouse_x},${state.mouse_y} | Hover ${status_hover}"
	props["status_text"] = escape_text(status_line)
	mut handlers := map[string]reactive.UiEventHandler{}
	handlers['start_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		track_pointer(mut state, mut e)
		if e.target_tag == 'divider' {
			state.resizing = true
			update_resize(mut state, mut e, true)
		}
	}
	handlers['start_split_resize'] = fn [mut state, main_top, left_panel_height, min_open, min_tree] (mut e reactive.UiEvent) {
		track_pointer(mut state, mut e)
		if e.target_tag == 'left-split-divider' {
			state.resizing_left_split = true
			update_left_split(mut state, e.mouse.y, main_top, left_panel_height, min_open, min_tree)
		}
	}
	handlers['resize_tracker'] = fn [mut state, main_top, left_panel_height, min_open, min_tree] (mut e reactive.UiEvent) {
		track_pointer(mut state, mut e)
		if state.resizing {
			update_resize(mut state, mut e, false)
		}
		if state.resizing_left_split {
			update_left_split(mut state, e.mouse.y, main_top, left_panel_height, min_open, min_tree)
		}
	}
	handlers['stop_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		track_pointer(mut state, mut e)
		if state.resizing {
			state.resizing = false
			update_resize(mut state, mut e, true)
		}
		if state.resizing_left_split {
			state.resizing_left_split = false
		}
	}
	open_panel_view := open_files_component(mut state, left_width, open_panel_height)
	file_tree_view := file_list_component(mut state, left_width, tree_panel_height)
	work_panel_view := build_editor_view(mut state, work_width, main_height, work_left, main_top)
	mut named_children := map[string][]reactive.VNode{}
	named_children['open_files'] = [open_panel_view]
	named_children['file_tree'] = [file_tree_view]
	named_children['work_panel'] = [work_panel_view]
	ctx := reactive.TemplateContext{
		props: props
		handlers: handlers
		named_children: named_children
	}
	return reactive.view_from_template(layout_template, ctx) or {
		reactive.relative(reactive.NodeSpec{
			tag: "error"
			props: reactive.TermProps{ width: viewport_width, height: viewport_height }
			children: [reactive.text(reactive.NodeSpec{
				tag: "error-text"
				props: reactive.TermProps{ text: "template error: " + err.msg() }
			})]
		})
	}
}

fn main() {
	mut state := LayoutState{}
	state.buffer = editor.new_text_buffer()
	state.tree = new_file_tree('.')
	refresh_file_entries(mut state)
	state.hover_tag = "none"
	root := fn [mut state] () reactive.VNode {
		return build_layout_view(mut state)
	}
	mut app := reactive.reactive_app(root)
	app.on_viewport_change(fn [mut state] (viewport reactive.TermRect) {
		state.viewport_width = viewport.width
		state.viewport_height = viewport.height
	})
	app.run()!
}
