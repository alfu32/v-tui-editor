import os
import reactive
import strings
import term.ui as tui
import editor
import time

const top_bar_height = 3
const status_bar_height = 2
const divider_width = 1
const min_left_width = 12
const min_right_width = 20
const editor_gutter_chars = editor.default_gutter_width + 2
const whitespace_runes = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
const editor_bg_color = reactive.TermColor{16, 20, 28}
const editor_fg_color = reactive.TermColor{210, 210, 210}
const editor_cursor_bg = reactive.TermColor{210, 210, 210}
const editor_cursor_fg = reactive.TermColor{20, 24, 32}
const editor_selection_bg = reactive.TermColor{60, 80, 120}
const editor_selection_fg = reactive.TermColor{255, 255, 255}
const file_refresh_interval_ms = 2000

enum FilePromptMode {
	none
	create_file
	create_folder
	rename_item
}

struct FilePromptState {
mut:
	active     bool
	mode       FilePromptMode = .none
	value      string
	parent_dir string
	target     string
}

struct ContextMenuState {
mut:
	visible bool
	entry   FileTreeEntry
	x       int
	y       int
}

fn escape_text(value string) string {
	return value
		.replace('&', '&amp;')
		.replace('<', '&lt;')
		.replace('>', '&gt;')
		.replace('"', '&quot;')
		.replace("'", '&#39;')
}

fn itos(value int) string {
	return '${value}'
}

struct LayoutState {
mut:
	left_panel_width     int = 26
	resizing             bool
	viewport_width       int       = 80
	viewport_height      int       = 24
	tree                 &FileTree = unsafe { nil }
	file_entries         []FileTreeEntry
	selected_file        string
	buffer               &editor.TextBuffer = unsafe { nil }
	editor_view_x        int
	editor_view_y        int
	editor_focused       bool
	editor_dragging      bool
	editor_rect          reactive.TermRect
	open_files           []string
	open_panel_height    int = 8
	resizing_left_split  bool
	mouse_x              int
	mouse_y              int
	hover_tag            string
	file_tree_scroll     int
	open_files_scroll    int
	tree_selected_path   string
	context_menu         ContextMenuState
	prompt               FilePromptState
	last_tree_refresh_ms i64
	status_message       string
	tree_rect            reactive.TermRect
	open_list_rect       reactive.TermRect
	tree_visible_rows    int
	open_visible_rows    int
	editor_follow_cursor bool = true
	buffer_dirty         bool
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

fn clamp_scroll(value int, visible int, total int) int {
	if visible <= 0 {
		return 0
	}
	mut max_scroll := total - visible
	if max_scroll < 0 {
		max_scroll = 0
	}
	mut clamped := value
	if clamped < 0 {
		clamped = 0
	}
	if clamped > max_scroll {
		clamped = max_scroll
	}
	return clamped
}

fn adjust_tree_scroll(mut state LayoutState, delta int) {
	visible := if state.tree_visible_rows > 0 { state.tree_visible_rows } else { 1 }
	state.file_tree_scroll = clamp_scroll(state.file_tree_scroll + delta, visible, state.file_entries.len)
}

fn adjust_open_scroll(mut state LayoutState, delta int) {
	visible := if state.open_visible_rows > 0 { state.open_visible_rows } else { 1 }
	state.open_files_scroll = clamp_scroll(state.open_files_scroll + delta, visible, state.open_files.len)
}

fn sync_viewport_from_renderer(mut state LayoutState, renderer reactive.Renderer) {
	state.viewport_width = renderer.ctx.viewport.width
	state.viewport_height = renderer.ctx.viewport.height
}

fn show_context_menu(mut state LayoutState, entry FileTreeEntry, pos reactive.TermPoint) {
	state.context_menu.visible = true
	state.context_menu.entry = entry
	state.context_menu.x = pos.x
	state.context_menu.y = pos.y
}

fn hide_context_menu(mut state LayoutState) {
	state.context_menu.visible = false
}

fn determine_creation_dir(state LayoutState) string {
	if isnil(state.tree) {
		return '.'
	}
	mut base := state.tree_selected_path
	if base.len == 0 {
		return state.tree.root
	}
	if os.is_dir(base) {
		return base
	}
	dir := os.dir(base)
	if dir.len == 0 {
		return state.tree.root
	}
	return dir
}

fn clamp_editor_view(mut state LayoutState, width int, height int) {
	mut visible_lines := height
	if visible_lines <= 0 {
		visible_lines = 1
	}
	mut max_line := state.buffer.lines.len - visible_lines
	if max_line < 0 {
		max_line = 0
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
	if state.editor_view_x < 0 {
		state.editor_view_x = 0
	}
	mut max_column := 0
	for line in state.buffer.lines {
		visual := editor.visual_length(line)
		if visual > max_column {
			max_column = visual
		}
	}
	mut max_view := max_column - content_width
	if max_view < 0 {
		max_view = 0
	}
	if state.editor_view_x > max_view {
		state.editor_view_x = max_view
	}
}

fn start_file_prompt(mut state LayoutState, mode FilePromptMode, parent string, initial string) {
	mut base := parent
	if base.len == 0 {
		base = if isnil(state.tree) { '.' } else { state.tree.root }
	}
	state.prompt.active = true
	state.prompt.mode = mode
	state.prompt.parent_dir = base
	state.prompt.value = initial
	if mode != .rename_item {
		state.prompt.target = ''
	}
	hide_context_menu(mut state)
}

fn start_rename_prompt(mut state LayoutState, entry FileTreeEntry) {
	start_file_prompt(mut state, .rename_item, os.dir(entry.full_path), entry.name)
	state.prompt.target = entry.full_path
}

fn cancel_prompt(mut state LayoutState) {
	state.prompt = FilePromptState{}
}

fn handle_prompt_input(mut state LayoutState, mut e reactive.UiEvent) bool {
	if !state.prompt.active || e.kind != .key_down {
		return false
	}
	code := int(e.key.code)
	match code {
		int(tui.KeyCode.enter) {
			complete_prompt(mut state)
			e.propagate = false
			return true
		}
		int(tui.KeyCode.escape) {
			cancel_prompt(mut state)
			e.propagate = false
			return true
		}
		int(tui.KeyCode.backspace) {
			if state.prompt.value.len > 0 {
				state.prompt.value = state.prompt.value[..state.prompt.value.len - 1]
			}
			e.propagate = false
			return true
		}
		int(tui.KeyCode.delete) {
			state.prompt.value = ''
			e.propagate = false
			return true
		}
		else {}
	}
	if e.key.char >= 32 && !e.key.ctrl && !e.key.alt && !e.key.meta {
		state.prompt.value += e.key.char.str()
		e.propagate = false
		return true
	}
	return false
}

fn complete_prompt(mut state LayoutState) {
	if !state.prompt.active {
		return
	}
	value := state.prompt.value.trim_space()
	if value.len == 0 {
		state.status_message = 'Name must not be empty'
		return
	}
	match state.prompt.mode {
		.create_file {
			create_file_entry(mut state, value)
		}
		.create_folder {
			create_folder_entry(mut state, value)
		}
		.rename_item {
			rename_entry(mut state, value)
		}
		else {}
	}
}

fn target_path(state LayoutState, name string) string {
	return os.join_path(state.prompt.parent_dir, name)
}

fn create_file_entry(mut state LayoutState, name string) {
	path := target_path(state, name)
	if os.exists(path) {
		state.status_message = 'Path already exists'
		return
	}
	os.write_file(path, '') or {
		state.status_message = 'Create failed: ${err.msg()}'
		return
	}
	state.status_message = 'Created ${name}'
	cancel_prompt(mut state)
	state.tree_selected_path = path
	refresh_after_fs_change(mut state)
}

fn create_folder_entry(mut state LayoutState, name string) {
	path := target_path(state, name)
	if os.exists(path) {
		state.status_message = 'Path already exists'
		return
	}
	os.mkdir_all(path) or {
		state.status_message = 'Folder failed: ${err.msg()}'
		return
	}
	state.status_message = 'Created folder ${name}'
	cancel_prompt(mut state)
	state.tree_selected_path = path
	refresh_after_fs_change(mut state)
}

fn rename_entry(mut state LayoutState, name string) {
	old_path := state.prompt.target
	if old_path.len == 0 {
		state.status_message = 'No target to rename'
		return
	}
	new_path := target_path(state, name)
	if os.exists(new_path) {
		state.status_message = 'Target already exists'
		return
	}
	os.mv(old_path, new_path) or {
		state.status_message = 'Rename failed: ${err.msg()}'
		return
	}
	state.status_message = 'Renamed to ${name}'
	update_paths_after_rename(mut state, old_path, new_path)
	cancel_prompt(mut state)
	refresh_after_fs_change(mut state)
}

fn delete_entry_at(mut state LayoutState, entry FileTreeEntry) {
	if entry.typ == 'folder' {
		os.rmdir_all(entry.full_path) or {
			state.status_message = 'Delete failed: ${err.msg()}'
			return
		}
	} else {
		os.rm(entry.full_path) or {
			state.status_message = 'Delete failed: ${err.msg()}'
			return
		}
	}
	state.status_message = 'Deleted ${entry.name}'
	if state.selected_file == entry.full_path {
		state.selected_file = ''
	}
	state.open_files = state.open_files.filter(it != entry.full_path)
	if state.tree_selected_path == entry.full_path {
		state.tree_selected_path = os.dir(entry.full_path)
	}
	refresh_after_fs_change(mut state)
}

fn update_paths_after_rename(mut state LayoutState, old_path string, new_path string) {
	if state.selected_file == old_path {
		state.selected_file = new_path
	}
	if state.tree_selected_path == old_path {
		state.tree_selected_path = new_path
	}
	for idx, value in state.open_files {
		if value == old_path {
			state.open_files[idx] = new_path
		}
	}
}

fn refresh_after_fs_change(mut state LayoutState) {
	if isnil(state.tree) {
		return
	}
	state.tree.refresh_open_nodes()
	refresh_file_entries(mut state)
	state.last_tree_refresh_ms = time.now().unix_milli()
}

fn dialog_box_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{30, 36, 50}
		foreground: reactive.TermColor{235, 235, 235}
		border:     'box_light_rounded'
		line:       'line_simple_simple'
	)
}

fn dialog_text_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{30, 36, 50}
		foreground: reactive.TermColor{230, 230, 230}
		border:     'empty'
		line:       'empty'
	)
}

fn button_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{70, 90, 130}
		foreground: reactive.TermColor{255, 255, 255}
		border:     'box_light_rounded'
		line:       'line_simple_simple'
	)
}

fn button_text_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{70, 90, 130}
		foreground: reactive.TermColor{255, 255, 255}
		border:     'empty'
		line:       'empty'
	)
}

fn context_menu_style() reactive.TermStyleSpec {
	return dialog_box_style()
}

fn context_item_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{42, 50, 70}
		foreground: reactive.TermColor{240, 240, 240}
		border:     'empty'
		line:       'empty'
	)
}

fn make_button(tag string, left int, top int, label string, handler reactive.UiEventHandler) reactive.VNode {
	mut width := label.len + 4
	if width < 8 {
		width = 8
	}
	mut text_left := (width - label.len) / 2
	if text_left < 1 {
		text_left = 1
	}
	return reactive.rect(reactive.NodeSpec{
		tag:      tag
		props:    reactive.TermProps{
			left:   left
			top:    top
			width:  width
			height: 3
		}
		style:    button_style()
		events:   [handler]
		children: [
			reactive.text(reactive.NodeSpec{
				props: reactive.TermProps{
					top:  1
					left: text_left
					text: label
				}
				style: button_text_style()
			}),
		]
	})
}

fn build_context_menu_view(mut state LayoutState) reactive.VNode {
	entry := state.context_menu.entry
	struct ContextAction {
		label   string
		handler reactive.UiEventHandler
	}

	mut actions := []ContextAction{}
	entry_copy := entry
	actions << ContextAction{
		label:   'Rename'
		handler: fn [mut state, entry_copy] (mut e reactive.UiEvent) {
			if e.kind != .mouse_down {
				return
			}
			start_rename_prompt(mut state, entry_copy)
		}
	}
	actions << ContextAction{
		label:   'Delete'
		handler: fn [mut state, entry_copy] (mut e reactive.UiEvent) {
			if e.kind != .mouse_down {
				return
			}
			hide_context_menu(mut state)
			delete_entry_at(mut state, entry_copy)
		}
	}
	if entry.typ == 'folder' {
		folder_copy := entry
		actions << ContextAction{
			label:   'New File'
			handler: fn [mut state, folder_copy] (mut e reactive.UiEvent) {
				if e.kind != .mouse_down {
					return
				}
				start_file_prompt(mut state, .create_file, folder_copy.full_path, '')
			}
		}
		actions << ContextAction{
			label:   'New Folder'
			handler: fn [mut state, folder_copy] (mut e reactive.UiEvent) {
				if e.kind != .mouse_down {
					return
				}
				start_file_prompt(mut state, .create_folder, folder_copy.full_path, '')
			}
		}
	}
	menu_width := 20
	menu_height := actions.len + 2
	mut left := state.context_menu.x
	mut top := state.context_menu.y
	if left + menu_width > state.viewport_width {
		left = state.viewport_width - menu_width
	}
	if left < 0 {
		left = 0
	}
	if top + menu_height > state.viewport_height {
		top = state.viewport_height - menu_height
	}
	if top < 0 {
		top = 0
	}
	mut children := []reactive.VNode{}
	for idx, action in actions {
		children << reactive.text(reactive.NodeSpec{
			tag:    'ctx-item-${idx}'
			props:  reactive.TermProps{
				top:    idx + 1
				left:   1
				width:  menu_width - 2
				height: 1
				text:   action.label
			}
			style:  context_item_style()
			events: [action.handler]
		})
	}
	return reactive.rect(reactive.NodeSpec{
		tag:      'context-menu'
		props:    reactive.TermProps{
			left:   left
			top:    top
			width:  menu_width
			height: menu_height
		}
		style:    context_menu_style()
		children: children
	})
}

fn prompt_style() reactive.TermStyleSpec {
	return dialog_text_style()
}

fn build_prompt_overlay(mut state LayoutState) reactive.VNode {
	mode_label := match state.prompt.mode {
		.create_file { 'New File' }
		.create_folder { 'New Folder' }
		.rename_item { 'Rename Item' }
		else { 'Input' }
	}
	mut width := if state.viewport_width > 40 {
		state.viewport_width - 20
	} else {
		state.viewport_width - 4
	}
	if width < 20 {
		width = state.viewport_width - 2
	}
	if width < 10 {
		width = 10
	}
	mut left := (state.viewport_width - width) / 2
	if left < 1 {
		left = 1
	}
	height := 9
	mut top := (state.viewport_height - height) / 2
	if top < 1 {
		top = 1
	}
	display_value := if state.prompt.value.len == 0 { '_' } else { state.prompt.value + '_' }
	mut children := []reactive.VNode{}
	children << reactive.text(reactive.NodeSpec{
		tag:   'prompt-title'
		props: reactive.TermProps{
			top:  1
			left: 2
			text: mode_label
		}
		style: prompt_style()
	})
	children << reactive.text(reactive.NodeSpec{
		tag:   'prompt-path'
		props: reactive.TermProps{
			top:  2
			left: 2
			text: 'In ${state.prompt.parent_dir}'
		}
		style: prompt_style()
	})
	children << reactive.text(reactive.NodeSpec{
		tag:   'prompt-value'
		props: reactive.TermProps{
			top:  4
			left: 2
			text: display_value
		}
		style: prompt_style()
	})
	children << reactive.text(reactive.NodeSpec{
		tag:   'prompt-help'
		props: reactive.TermProps{
			top:  5
			left: 2
			text: 'Enter to confirm • Esc to cancel'
		}
		style: prompt_style()
	})
	confirm_label := match state.prompt.mode {
		.rename_item { 'Rename' }
		.create_file { 'Create' }
		.create_folder { 'Create' }
		else { 'OK' }
	}
	mut button_top := height - 4
	if button_top < 1 {
		button_top = 1
	}
	cancel_left := if width > 22 { width - 22 } else { 2 }
	confirm_left := if width > 12 { width - 12 } else { cancel_left + 10 }
	children << make_button('prompt-cancel', cancel_left, button_top, 'Cancel', fn [mut state] (mut e reactive.UiEvent) {
		if e.kind == .mouse_down {
			cancel_prompt(mut state)
		}
	})
	children << make_button('prompt-confirm', confirm_left, button_top, confirm_label,
		fn [mut state] (mut e reactive.UiEvent) {
		if e.kind == .mouse_down {
			complete_prompt(mut state)
		}
	})
	return reactive.rect(reactive.NodeSpec{
		tag:      'prompt-overlay'
		props:    reactive.TermProps{
			left:   left
			top:    top
			width:  width
			height: height
		}
		style:    dialog_box_style()
		children: children
	})
}

fn handle_root_event(mut state LayoutState, mut e reactive.UiEvent) {
	sync_viewport_from_renderer(mut state, e.renderer)
	if state.prompt.active {
		if handle_prompt_input(mut state, mut e) {
			return
		}
	}
	if e.kind == .mouse_down && !e.mouse.buttons.right {
		hide_context_menu(mut state)
	}
}

fn build_top_title_node(state LayoutState) reactive.VNode {
	mut title := 'V Reactive Workspace'
	if state.selected_file.len > 0 {
		title += ' - ${state.selected_file}'
	} else if !isnil(state.tree) {
		title += ' - ${state.tree.root}'
	}
	return reactive.text(reactive.NodeSpec{
		tag:   'top-title'
		props: reactive.TermProps{
			top:  1
			left: 2
			text: title
		}
		style: top_bar_text_style()
	})
}

fn build_close_button(mut state LayoutState, viewport_width int) reactive.VNode {
	mut left := viewport_width - 5
	if left < 2 {
		left = 2
	}
	return reactive.text(reactive.NodeSpec{
		tag:    'top-close'
		props:  reactive.TermProps{
			top:  1
			left: left
			text: '[X]'
		}
		style:  close_button_style()
		events: [
			fn [mut state] (mut e reactive.UiEvent) {
				if e.kind == .mouse_down {
					e.renderer.app.will_exit(0)
				}
			},
		]
	})
}

fn tree_panel_event_handler(mut state LayoutState) reactive.UiEventHandler {
	return fn [mut state] (mut e reactive.UiEvent) {
		if state.prompt.active {
			return
		}
		if e.kind == .mouse_move && e.mouse.wheel != 0 {
			if state.tree_rect.contains_point(reactive.TermPoint{
				x: e.mouse.x
				y: e.mouse.y
			})
			{
				adjust_tree_scroll(mut state, e.mouse.wheel)
			}
		}
		if e.kind == .key_down {
			match int(e.key.code) {
				int(tui.KeyCode.page_up) {
					adjust_tree_scroll(mut state, -state.tree_visible_rows)
				}
				int(tui.KeyCode.page_down) {
					adjust_tree_scroll(mut state, state.tree_visible_rows)
				}
				else {}
			}
		}
	}
}

fn open_panel_event_handler(mut state LayoutState) reactive.UiEventHandler {
	return fn [mut state] (mut e reactive.UiEvent) {
		if state.prompt.active {
			return
		}
		if e.kind == .mouse_move && e.mouse.wheel != 0 {
			if state.open_list_rect.contains_point(reactive.TermPoint{
				x: e.mouse.x
				y: e.mouse.y
			})
			{
				adjust_open_scroll(mut state, e.mouse.wheel)
			}
		}
		if e.kind == .key_down {
			match int(e.key.code) {
				int(tui.KeyCode.page_up) {
					adjust_open_scroll(mut state, -state.open_visible_rows)
				}
				int(tui.KeyCode.page_down) {
					adjust_open_scroll(mut state, state.open_visible_rows)
				}
				else {}
			}
		}
	}
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
	sync_viewport_from_renderer(mut state, e.renderer)
	state.mouse_x = e.mouse.x
	state.mouse_y = e.mouse.y
	if e.target_tag.len > 0 {
		state.hover_tag = e.target_tag
	}
}

fn read_file_preview(path string) []string {
	content := os.read_bytes(path) or { return ['Failed to open ${path}: ${err.msg()}'] }
	return (content.bytestr()).split_into_lines()
}

fn add_open_file(mut state LayoutState, path string) {
	if path.len == 0 {
		return
	}
	if path in state.open_files {
		return
	}
	state.open_files << path
}

fn build_file_list_markup(mut state LayoutState, left_width int, main_height int, mut handlers map[string]reactive.UiEventHandler) string {
	mut b := strings.new_builder(256)
	mut available := main_height - 3
	if available < 1 {
		available = 1
	}
	state.tree_visible_rows = available
	state.file_tree_scroll = clamp_scroll(state.file_tree_scroll, available, state.file_entries.len)
	row_height := 1
	mut row := 0
	for idx := state.file_tree_scroll; idx < state.file_entries.len; idx++ {
		entry := state.file_entries[idx]
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
		if entry.full_path == state.tree_selected_path {
			fg = '#ffffff'
			bg = '#2f3e5c'
		} else if entry.typ == 'file' && entry.full_path == state.selected_file {
			fg = '#f5f5f5'
			bg = '#2a364c'
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
			state.tree_selected_path = entry_copy.full_path
			if e.mouse.buttons.right && e.kind == .mouse_down {
				show_context_menu(mut state, entry_copy, reactive.TermPoint{
					x: e.mouse.x
					y: e.mouse.y
				})
				return
			}
			hide_context_menu(mut state)
			if entry_copy.typ == 'folder' {
				state.tree.toggle(entry_copy.full_path)
				refresh_file_entries(mut state)
			} else {
				autosave_current_file(mut state)
				state.selected_file = entry_copy.full_path
				if isnil(state.buffer) {
					state.buffer = editor.new_text_buffer()
				}
				text := os.read_bytes(entry_copy.full_path) or { []u8{} }
				state.buffer.load_text(text.bytestr())
				state.buffer_dirty = false
				state.editor_view_y = 0
				state.editor_view_x = 0
				state.editor_follow_cursor = true
				add_open_file(mut state, entry_copy.full_path)
			}
		}
		b.write_string("\n\t\t\t<text tag=\"${node_tag}\" onmousedown={" + handler_name +
			"} style=\"top:${line_top};left:${padding_left};width:${entry_width};height:1;fg:${fg};bg:${bg}\">")
		b.write_string(label)
		b.write_string('</text>')
		row++
	}
	if state.file_entries.len == 0 {
		b.write_string('\n\t\t\t<text style="top:3;left:2;fg:#888888">(no files)</text>')
	}
	return b.str()
}

fn truncate_line(line string, limit int) string {
	if limit <= 0 {
		return ''
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
		border:     'empty'
		line:       'empty'
	)
}

fn editor_gutter_background_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_bg_color.lighter(10)
		foreground: editor_fg_color
		border:     'empty'
		line:       'empty'
	)
}

fn editor_selection_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_selection_bg
		foreground: editor_selection_fg
		border:     'empty'
		line:       'empty'
	)
}

fn editor_cursor_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: editor_cursor_bg
		foreground: editor_cursor_fg
		border:     'empty'
		line:       'empty'
	)
}

fn top_bar_text_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{43, 52, 77}
		foreground: reactive.TermColor{240, 240, 240}
		border:     'empty'
		line:       'empty'
	)
}

fn close_button_style() reactive.TermStyleSpec {
	return reactive.make_stylesheet(
		background: reactive.TermColor{43, 52, 77}
		foreground: reactive.TermColor{255, 143, 143}
		border:     'empty'
		line:       'empty'
	)
}

fn refresh_file_entries(mut state LayoutState) {
	if isnil(state.tree) {
		return
	}
	state.file_entries = state.tree.flattened()
}

pub const spaces = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]

fn build_editor_view(mut state LayoutState, width int, height int, work_left int, main_top int) reactive.VNode {
	state.editor_rect = reactive.TermRect{
		x:      work_left
		y:      main_top
		width:  width
		height: height
	}
	if isnil(state.buffer) {
		state.buffer = editor.new_text_buffer()
	}
	if state.editor_follow_cursor {
		ensure_cursor_visible(mut state, width, height)
	} else {
		clamp_editor_view(mut state, width, height)
	}
	mut content_width := width - editor_gutter_chars
	if content_width < 1 {
		content_width = 1
	}
	viewport := editor.EditorViewport{
		x:      state.editor_view_x
		y:      state.editor_view_y
		width:  content_width
		height: height
	}
	slice := state.buffer.viewport_slice(viewport)
	mut children := []reactive.VNode{}
	children << reactive.rect(reactive.NodeSpec{
		props: reactive.TermProps{
			width:  width
			height: height
		}
		style: editor_background_style()
	})
	for idx, line in slice.lines {
		mut left := 0
		children << reactive.text(reactive.NodeSpec{
			tag:   'editor-gutter'
			props: reactive.TermProps{
				top:  idx
				left: left
				text: line.gutter
			}
			style: editor_gutter_background_style()
		})
		left += editor_gutter_chars
		for seg in line.segments {
			mut style := editor_background_style()
			if seg.selected {
				style = editor_selection_style()
			}
			if seg.text.len == 0 {
				continue
			}
			children << reactive.text(reactive.NodeSpec{
				props: reactive.TermProps{
					top:  idx
					left: left
					text: seg.text
				}
				style: style
			})
			left += seg.text.len
		}
	}

	if cursor := slice.cursor {
		mut column := cursor.column
		if column < 0 {
			column = 0
		}
		mut overlay_char := '_'
		if cursor.char.len > 0 {
			mut runes := cursor.char.runes()
			if runes.len > 0 {
				if runes[0] !in whitespace_runes {
					overlay_char = runes[0].str()
				}
			}
		}
		children << reactive.text(reactive.NodeSpec{
			tag:   'editor-cursor'
			props: reactive.TermProps{
				top:  cursor.line
				left: editor_gutter_chars + column
				text: overlay_char
			}
			style: editor_cursor_style()
		})
	}
	editor_handler := fn [mut state, width, height, work_left, main_top] (mut e reactive.UiEvent) {
		handle_editor_event(mut state, width, height, work_left, main_top, mut e)
	}
	return reactive.relative(reactive.NodeSpec{
		tag:      'code-editor'
		props:    reactive.TermProps{
			width:  width
			height: height
		}
		style:    editor_background_style()
		children: children
		events:   [editor_handler]
	})
}

fn editor_hit_test(rect reactive.TermRect, x int, y int) bool {
	return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
}

fn handle_editor_event(mut state LayoutState, width int, height int, work_left int, main_top int, mut e reactive.UiEvent) {
	if isnil(state.buffer) {
		return
	}
	if state.prompt.active {
		return
	}
	sync_viewport_from_renderer(mut state, e.renderer)
	if e.kind == .mouse_down {
		if editor_hit_test(state.editor_rect, e.mouse.x, e.mouse.y) {
			state.editor_focused = true
			pos := editor_position_from_mouse(state, e.mouse.x, e.mouse.y)
			state.buffer.start_selection(pos)
			state.editor_follow_cursor = true
			state.editor_dragging = e.mouse.buttons.left
			ensure_cursor_visible(mut state, width, height)
		} else {
			state.editor_focused = false
		}
		return
	}
	if e.kind == .mouse_move {
		if e.mouse.wheel != 0 && editor_hit_test(state.editor_rect, e.mouse.x, e.mouse.y) {
			state.editor_follow_cursor = false
			state.editor_view_y += e.mouse.wheel
			clamp_editor_view(mut state, width, height)
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
		state.editor_follow_cursor = true
	}
}

fn handle_editor_key(mut state LayoutState, width int, height int, mut e reactive.UiEvent) {
	if isnil(state.buffer) {
		return
	}
	if state.prompt.active {
		return
	}
	mut handled := false
	mut content_changed := false
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
			content_changed = true
		}
		int(tui.KeyCode.backspace) {
			state.buffer.delete_backspace()
			handled = true
			content_changed = true
		}
		int(tui.KeyCode.delete) {
			state.buffer.delete_forward()
			handled = true
			content_changed = true
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
				if state.buffer.cut_selection() {
					content_changed = true
					handled = true
				}
			}
			int(tui.KeyCode.v) {
				state.buffer.paste_clipboard()
				handled = true
				content_changed = true
			}
			int(tui.KeyCode.a) {
				state.buffer.select_all()
				handled = true
			}
			int(tui.KeyCode.s) {
				save_current_file(mut state)
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
			content_changed = true
		}
	}
	if handled {
		ensure_cursor_visible(mut state, width, height)
	}
	if content_changed {
		state.buffer_dirty = true
	}
}

fn save_current_file(mut state LayoutState) {
	if isnil(state.buffer) || state.selected_file.len == 0 {
		state.status_message = 'No file selected'
		return
	}
	content := state.buffer.text()
	os.write_file(state.selected_file, content) or {
		state.status_message = 'Save failed: ${err.msg()}'
		return
	}
	state.status_message = 'Saved ${os.file_name(state.selected_file)}'
	state.buffer_dirty = false
}

fn autosave_current_file(mut state LayoutState) {
	if state.buffer_dirty {
		save_current_file(mut state)
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
	mut visual_column_value := mouse_x - state.editor_rect.x - editor_gutter_chars +
		state.editor_view_x
	if visual_column_value < 0 {
		visual_column_value = 0
	}
	line_text := state.buffer.lines[line]
	mut max_visual := editor.visual_length(line_text)
	if visual_column_value > max_visual {
		visual_column_value = max_visual
	}
	actual_column := editor.actual_column(line_text, visual_column_value)
	return editor.Position{line, actual_column}
}

fn ensure_cursor_visible(mut state LayoutState, width int, height int) {
	mut visible_lines := if height > 0 { height } else { 1 }
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
	mut content_width := width - editor_gutter_chars
	if content_width <= 0 {
		content_width = 1
	}
	line_text := if state.buffer.cursor.line >= 0
		&& state.buffer.cursor.line < state.buffer.lines.len {
		state.buffer.lines[state.buffer.cursor.line]
	} else {
		''
	}
	cursor_visual := editor.visual_column(line_text, state.buffer.cursor.column)
	if cursor_visual < state.editor_view_x {
		state.editor_view_x = cursor_visual
	}
	if cursor_visual >= state.editor_view_x + content_width {
		state.editor_view_x = cursor_visual - content_width + 1
	}
	clamp_editor_view(mut state, width, height)
}

fn open_files_component(mut state LayoutState, width int, height int) reactive.VNode {
	mut b := strings.new_builder(128)
	mut available := if height <= 0 { 1 } else { height }
	state.open_visible_rows = available
	state.open_files_scroll = clamp_scroll(state.open_files_scroll, available, state.open_files.len)
	for idx, path in state.open_files {
		if idx < state.open_files_scroll {
			continue
		}
		row := idx - state.open_files_scroll
		if row >= available {
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
		b.write_string('\n\t<text tag="${node_tag}" onclick={' + handler_name +
			'} style="top:${row + 1};left:2;width:${content_width};height:1;fg:${fg};bg:${bg}">')
		b.write_string(display)
		b.write_string('</text>')
	}
	if state.open_files.len == 0 {
		b.write_string('\n\t<text style="top:1;left:2;fg:#888888">(no open files)</text>')
	}
	template :=
		'<relative tag="open-files" style="width:{{width}};height:{{height}}"><rect style="width:{{width}};height:{{height}};bg:#20283a"/>' +
		b.str() + '\n</relative>'
	mut handlers := map[string]reactive.UiEventHandler{}
	for idx, path in state.open_files {
		node_tag := 'open-${idx}'
		handlers['open_click_${idx}'] = fn [mut state, path, node_tag] (mut e reactive.UiEvent) {
			if e.target_tag != node_tag {
				return
			}
			hide_context_menu(mut state)
			autosave_current_file(mut state)
			state.selected_file = path
			state.tree_selected_path = path
			if isnil(state.buffer) {
				state.buffer = editor.new_text_buffer()
			}
			text := os.read_bytes(path) or { []u8{} }
			state.buffer.load_text(text.bytestr())
			state.buffer_dirty = false
			state.editor_view_y = 0
			state.editor_view_x = 0
			state.editor_follow_cursor = true
			add_open_file(mut state, path)
		}
	}
	ctx := reactive.TemplateContext{
		props:    {
			'width':  itos(width)
			'height': itos(height)
		}
		handlers: handlers
	}
	mut view := reactive.view_from_template(template, ctx) or {
		reactive.text(reactive.NodeSpec{
			tag:   'open-files-error'
			props: reactive.TermProps{
				text: 'open files error: ' + err.msg()
			}
		})
	}
	view.events << open_panel_event_handler(mut state)
	return view
}

fn file_list_component(mut state LayoutState, left_width int, main_height int) reactive.VNode {
	mut local_handlers := map[string]reactive.UiEventHandler{}
	items_markup := build_file_list_markup(mut state, left_width, main_height, mut local_handlers)
	template := r'
<relative tag="file-list" style="width:{{width}};height:{{height}}">
	<rect style="width:{{width}};height:{{height}};bg:#1f2736"/>
	<text style="top:1;left:2;fg:#9ddcff">Explorer</text>
	<text tag="add-file" onclick={create_file} style="top:1;left:{{file_btn_left}};fg:#8de78d">+f</text>
	<text tag="add-folder" onclick={create_folder} style="top:1;left:{{dir_btn_left}};fg:#8de78d">+d</text>
	@@ITEMS@@
</relative>
'.trim_indent()
	component_template := template.replace('@@ITEMS@@', items_markup)
	local_handlers['create_file'] = fn [mut state] (mut e reactive.UiEvent) {
		if e.kind != .mouse_down {
			return
		}
		hide_context_menu(mut state)
		start_file_prompt(mut state, .create_file, determine_creation_dir(state), '')
	}
	local_handlers['create_folder'] = fn [mut state] (mut e reactive.UiEvent) {
		if e.kind != .mouse_down {
			return
		}
		hide_context_menu(mut state)
		start_file_prompt(mut state, .create_folder, determine_creation_dir(state), '')
	}
	btn_left := if left_width > 8 { left_width - 8 } else { 1 }
	dir_left := if left_width > 4 { left_width - 4 } else { 2 }
	ctx := reactive.TemplateContext{
		props:    {
			'width':         itos(left_width)
			'height':        itos(main_height)
			'file_btn_left': itos(btn_left)
			'dir_btn_left':  itos(dir_left)
		}
		handlers: local_handlers
	}
	mut view := reactive.view_from_template(component_template, ctx) or {
		reactive.text(reactive.NodeSpec{
			tag:   'file-list-error'
			props: reactive.TermProps{
				text: 'file list error: ' + err.msg()
			}
		})
	}
	view.events << tree_panel_event_handler(mut state)
	return view
}

const layout_template = r'
<relative tag="root" style="width:{{viewport_width}};height:{{viewport_height}};bg:#181c20" onmousemove={resize_tracker} onmouseup={stop_resize}>
	<rect tag="top-bar" style="width:{{viewport_width}};height:{{top_bar_height}};bg:#2b344d">
		<slot name="top_title"/>
		<slot name="top_controls"/>
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
	now_ms := time.now().unix_milli()
	if state.last_tree_refresh_ms == 0
		|| now_ms - state.last_tree_refresh_ms > file_refresh_interval_ms {
		refresh_after_fs_change(mut state)
	}
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
	state.open_list_rect = reactive.TermRect{
		x:      0
		y:      main_top
		width:  left_width
		height: open_panel_height
	}
	state.tree_rect = reactive.TermRect{
		x:      0
		y:      main_top + open_panel_height + 1
		width:  left_width
		height: tree_panel_height
	}
	mut props := map[string]string{}
	props['viewport_width'] = itos(viewport_width)
	props['viewport_height'] = itos(viewport_height)
	props['top_bar_height'] = itos(top_bar_height)
	props['status_height'] = itos(status_bar_height)
	props['status_top'] = itos(status_top)
	props['main_top'] = itos(top_bar_height)
	props['main_height'] = itos(main_height)
	props['left_width'] = itos(left_width)
	props['divider_left'] = itos(left_width)
	props['divider_width'] = itos(divider_width)
	props['work_left'] = itos(work_left)
	props['work_width'] = itos(work_width)
	props['open_panel_height'] = itos(open_panel_height)
	props['open_panel_height_plus_one'] = itos(open_panel_height + 1)
	props['tree_panel_height'] = itos(tree_panel_height)
	status_hover := if state.hover_tag.len > 0 { state.hover_tag } else { 'none' }
	mut status_line := 'Panel ${left_width}px | Editor ${work_width}px | Mouse ${state.mouse_x},${state.mouse_y} | Hover ${status_hover}'
	if state.status_message.len > 0 {
		status_line += ' | ${state.status_message}'
	}
	props['status_text'] = escape_text(status_line)
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
			update_left_split(mut state, e.mouse.y, main_top, left_panel_height, min_open,
				min_tree)
		}
	}
	handlers['resize_tracker'] = fn [mut state, main_top, left_panel_height, min_open, min_tree] (mut e reactive.UiEvent) {
		track_pointer(mut state, mut e)
		if state.resizing {
			update_resize(mut state, mut e, false)
		}
		if state.resizing_left_split {
			update_left_split(mut state, e.mouse.y, main_top, left_panel_height, min_open,
				min_tree)
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
	work_panel_view := build_editor_view(mut state, work_width, main_height, work_left,
		main_top)
	mut named_children := map[string][]reactive.VNode{}
	named_children['open_files'] = [open_panel_view]
	named_children['file_tree'] = [file_tree_view]
	named_children['work_panel'] = [work_panel_view]
	named_children['top_title'] = [build_top_title_node(state)]
	named_children['top_controls'] = [build_close_button(mut state, viewport_width)]
	ctx := reactive.TemplateContext{
		props:          props
		handlers:       handlers
		named_children: named_children
	}
	mut view := reactive.view_from_template(layout_template, ctx) or {
		reactive.relative(reactive.NodeSpec{
			tag:      'error'
			props:    reactive.TermProps{
				width:  viewport_width
				height: viewport_height
			}
			children: [
				reactive.text(reactive.NodeSpec{
					tag:   'error-text'
					props: reactive.TermProps{
						text: 'template error: ' + err.msg()
					}
				}),
			]
		})
	}
	view.events << fn [mut state] (mut e reactive.UiEvent) {
		handle_root_event(mut state, mut e)
	}
	if state.context_menu.visible {
		view.children << build_context_menu_view(mut state)
	}
	if state.prompt.active {
		view.children << build_prompt_overlay(mut state)
	}
	return view
}

fn main() {
	mut state := LayoutState{}
	state.buffer = editor.new_text_buffer()
	state.buffer_dirty = false
	state.tree = new_file_tree('.')
	state.tree_selected_path = state.tree.root
	refresh_file_entries(mut state)
	state.hover_tag = 'none'
	state.last_tree_refresh_ms = time.now().unix_milli()
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
