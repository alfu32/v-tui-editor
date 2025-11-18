import reactive

const top_bar_height = 3
const status_bar_height = 2
const divider_width = 1
const min_left_width = 12
const min_right_width = 20

fn itos(value int) string {
	return '${value}'
}

struct LayoutState {
mut:
	left_panel_width int = 26
	resizing         bool
	viewport_width   int = 80
	viewport_height  int = 24
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

const layout_template = r'
<relative tag="root" style="width:{{viewport_width}};height:{{viewport_height}};bg:#181c20" onmousemove={drag_resize} onmouseup={stop_resize}>
	<rect tag="top-bar" style="width:{{viewport_width}};height:{{top_bar_height}};bg:#2b344d">
		<text style="top:1;left:2;fg:#f0f0f0">V Reactive Workspace</text>
	</rect>
	<rect tag="status-bar" style="top:{{status_top}};width:{{viewport_width}};height:{{status_height}};bg:#222730">
		<text style="top:1;left:2;fg:#c0c0c0">Panel {{left_width}}px | Editor {{work_width}}px | Drag divider to resize. Press Esc to exit.</text>
	</rect>
	<relative tag="main" style="top:{{main_top}};width:{{viewport_width}};height:{{main_height}}">
		<rect tag="left-panel" style="width:{{left_width}};height:{{main_height}};bg:#1f2736;fg:#f0f0f0">
			<text style="top:1;left:2;fg:#9ddcff">Explorer</text>
			<text style="top:3;left:2;fg:#d0d0d0">- renderer.v</text>
			<text style="top:4;left:2;fg:#d0d0d0">- template.v</text>
			<text style="top:5;left:2;fg:#d0d0d0">- layout.templ</text>
		</rect>
		<rect tag="divider" style="left:{{divider_left}};width:{{divider_width}};height:{{main_height}};bg:#888a90" onmousedown={start_resize} onmousemove={drag_resize} onmouseup={stop_resize} />
		<relative tag="work" style="left:{{work_left}};width:{{work_width}};height:{{main_height}};bg:#10141c">
			<rect tag="work-surface" style="width:{{work_width}};height:{{main_height}};bg:#101820">
				<text style="top:1;left:2;fg:#9cdcfe">fn render_workspace() &#123;</text>
				<text style="top:2;left:4;fg:#dcdcaa">// Build layouts with &lt;relative&gt;, &lt;rect&gt; and &lt;text&gt;</text>
				<text style="top:3;left:4;fg:#c586c0">resize_left_panel(mouse_drag)</text>
				<text style="top:4;left:2;fg:#9cdcfe">&#125;</text>
			</rect>
		</relative>
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
	mut handlers := map[string]reactive.UiEventHandler{}
	handlers['start_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		state.resizing = true
		update_resize(mut state, mut e, true)
	}
	handlers['drag_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		update_resize(mut state, mut e, false)
	}
	handlers['stop_resize'] = fn [mut state] (mut e reactive.UiEvent) {
		state.resizing = false
		update_resize(mut state, mut e, true)
	}
	ctx := reactive.TemplateContext{
		props: props
		handlers: handlers
	}
	return reactive.view_from_template(layout_template, ctx) or {
		reactive.relative(reactive.NodeSpec{
			tag: 'error'
			props: reactive.TermProps{ width: viewport_width, height: viewport_height }
			children: [reactive.text(reactive.NodeSpec{
				tag: 'error-text'
				props: reactive.TermProps{ text: 'template error: ' + err.msg() }
			})]
		})
	}
}

fn main() {
	mut state := LayoutState{}
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
