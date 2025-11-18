import os
import reactive
import strings

const top_bar_height = 3
const status_bar_height = 2
const divider_width = 1
const min_left_width = 12
const min_right_width = 20

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
	file_lines       []string
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
				state.file_lines = read_file_preview(entry_copy.full_path)
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

fn build_file_content_markup(state LayoutState, work_width int, main_height int) string {
	mut b := strings.new_builder(256)
	mut lines := state.file_lines.clone()
	if state.selected_file.len == 0 || lines.len == 0 {
		lines = ["Click a file to preview its contents."]
	}
	mut max_lines := main_height - 2
	if max_lines < 1 {
		max_lines = 1
	}
	mut width_limit := work_width - 4
	if width_limit < 1 {
		width_limit = work_width
	}
	for i in 0 .. max_lines {
		if i >= lines.len {
			break
		}
		line := escape_text(truncate_line(lines[i], width_limit))
		b.write_string("\n\t\t\t\t<text style=\"top:${i + 1};left:2;fg:#d0d0d0\">")
		b.write_string(line)
		b.write_string("</text>")
	}
	return b.str()
}

fn refresh_file_entries(mut state LayoutState) {
	if isnil(state.tree) {
		return
	}
	state.file_entries = state.tree.flattened()
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

fn file_content_component(state LayoutState, work_width int, main_height int) reactive.VNode {
	lines_markup := build_file_content_markup(state, work_width, main_height)
	template := r'
<relative tag="file-content" style="width:{{width}};height:{{height}}">
	@@LINES@@
</relative>
'.trim_indent()
	component_template := template.replace('@@LINES@@', lines_markup)
	ctx := reactive.TemplateContext{
		props: {
			'width': itos(work_width)
			'height': itos(main_height)
		}
	}
	return reactive.view_from_template(component_template, ctx) or {
		reactive.text(reactive.NodeSpec{
			tag: 'file-content-error'
			props: reactive.TermProps{ text: 'file content error: ' + err.msg() }
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
			<slot name="left_panel"/>
		</rect>
		<rect tag="divider" style="left:{{divider_left}};width:{{divider_width}};height:{{main_height}};bg:#888a90" onmousedown={start_resize} onmousemove={resize_tracker} onmouseup={stop_resize} />
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
	handlers['resize_tracker'] = fn [mut state] (mut e reactive.UiEvent) {
		if state.resizing {
			track_pointer(mut state, mut e)
			update_resize(mut state, mut e, false)
		}
	}
	handlers['stop_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		if state.resizing {
			track_pointer(mut state, mut e)
			state.resizing = false
			update_resize(mut state, mut e, true)
		}
	}
	left_panel_view := file_list_component(mut state, left_width, main_height)
	work_panel_view := file_content_component(state, work_width, main_height)
	mut named_children := map[string][]reactive.VNode{}
	named_children['left_panel'] = [left_panel_view]
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
