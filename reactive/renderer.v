module reactive

import term.ui as tui

// --------------------- Geometry & styling ---------------------

pub struct TermRect {
pub mut:
	x      int
	y      int
	width  int
	height int
}

// copy: explicit, even though assignment already copies
pub fn (r TermRect) copy() TermRect {
	return TermRect{
		x: r.x
		y: r.y
		width: r.width
		height: r.height
	}
}

pub fn (r TermRect) is_empty() bool {
	return r.width == 0 && r.height == 0
}

// geometric union (minimal AABB containing both)
pub fn (a TermRect) add(b TermRect) TermRect {
	if a.is_empty() {
		return b.copy()
	}
	if b.is_empty() {
		return a.copy()
	}
	x1 := if a.x < b.x { a.x } else { b.x }
	y1 := if a.y < b.y { a.y } else { b.y }
	x2 := if a.x + a.width > b.x + b.width { a.x + a.width } else { b.x + b.width }
	y2 := if a.y + a.height > b.y + b.height { a.y + a.height } else { b.y + b.height }
	return TermRect{
		x: x1
		y: y1
		width: x2 - x1
		height: y2 - y1
	}
}
pub struct TermProps {
pub mut:
	top    int
	left   int
	width  int
	height int
	text   string
}

pub struct TermColor {
pub:
	r u8
	g u8
	b u8
}

pub struct TermStyleState {
pub:
	background TermColor
	foreground TermColor
}

pub struct TermStyleSpec {
pub:
	default TermStyleState
	hover   ?TermStyleState
	focus   ?TermStyleState
}

fn default_style() TermStyleSpec {
	return TermStyleSpec{
		default: TermStyleState{
			background: TermColor{0, 0, 0}
			foreground: TermColor{255, 255, 255}
		}
		hover:   none
		focus:   none
	}
}

// --------------------- Events ---------------------

pub enum UiEventKind {
	click
	mouse_move
	mouse_down
	mouse_up
	key_down
	key_up
	focus
	blur
}

pub struct KeyState {
pub mut:
	code  u32
	char  rune
	ctrl  bool
	alt   bool
	shift bool
	meta  bool
}

pub struct MouseButtons {
pub mut:
	left   bool
	right  bool
	middle bool
}

pub struct MouseState {
pub mut:
	x       int
	y       int
	buttons MouseButtons
	wheel   int
}

pub struct UiEvent {
pub mut:
	kind      UiEventKind
	target    int   // id in rendered list
	path      []int // outer -> inner, ids
	key       KeyState
	mouse     MouseState
	propagate bool = true
}

pub type UiEventHandler = fn (mut UiEvent)

pub struct TermEventHandlers {
pub:
	click      ?UiEventHandler = none
	mouse_move ?UiEventHandler = none
	mouse_down ?UiEventHandler = none
	mouse_up   ?UiEventHandler = none
	key_down   ?UiEventHandler = none
	key_up     ?UiEventHandler = none
	focus      ?UiEventHandler = none
	blur       ?UiEventHandler = none
}

// --------------------- Rendered nodes for events ---------------------

pub struct RenderedNode {
pub:
	id     int
	rect   TermRect
	style  TermStyleSpec
	events TermEventHandlers
}

// Context passed down every render pass
pub struct RenderContext {
pub mut:
	tui      &tui.Context
	viewport TermRect
	nodes    []RenderedNode
}

pub fn (mut ctx RenderContext) register(rect TermRect, style TermStyleSpec, events TermEventHandlers) int {
	id := ctx.nodes.len
	ctx.nodes << RenderedNode{
		id:     id
		rect:   rect
		style:  style
		events: events
	}
	return id
}

// --------------------- VNode & render model ---------------------

pub type RenderFn = fn (node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect

pub struct VNode {
pub:
	render   RenderFn
	props    TermProps
	style    TermStyleSpec
	events   TermEventHandlers
	children []VNode
}

pub struct NodeSpec {
pub:
	props    TermProps         = TermProps{}
	style    TermStyleSpec     = default_style()
	events   TermEventHandlers = TermEventHandlers{}
	children []VNode           = []VNode{}
}

// Rect union helper
fn union_rect(a TermRect, b TermRect) TermRect {
	if a.width == 0 && a.height == 0 {
		return b
	}
	if b.width == 0 && b.height == 0 {
		return a
	}
	x1 := if a.x < b.x { a.x } else { b.x }
	y1 := if a.y < b.y { a.y } else { b.y }
	x2 := if a.x + a.width > b.x + b.width { a.x + a.width } else { b.x + b.width }
	y2 := if a.y + a.height > b.y + b.height { a.y + a.height } else { b.y + b.height }
	return TermRect{
		x:      x1
		y:      y1
		width:  x2 - x1
		height: y2 - y1
	}
}

// --------------------- Built-in components (all just VNodes) ---------------------

// BOX: filled rect, grows parent, children rendered inside.
fn render_box(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut rect := TermRect{
		x:      origin_x + node.props.left
		y:      origin_y + node.props.top
		width:  node.props.width
		height: node.props.height
	}
	if rect.width == 0 {
		rect.width = ctx.viewport.width
	}
	if rect.height == 0 {
		rect.height = ctx.viewport.height
	}

	_ = ctx.register(rect, node.style, node.events)

	// draw immediately
	mut s := node.style.default
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_fg_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	for dy := 0; dy < rect.height; dy++ {
		for dx := 0; dx < rect.width; dx++ {
			ctx.tui.draw_text(rect.x + dx, rect.y + dy, ' ')
		}
	}

	mut combined := rect
	for child in node.children {
		child_rect := child.render(child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}

pub fn box(spec NodeSpec) VNode {
	return VNode{
		render:   render_box
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// BORDER BOX: border only, grows parent, children inside.
fn render_border_box(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut rect := TermRect{
		x:      origin_x + node.props.left
		y:      origin_y + node.props.top
		width:  node.props.width
		height: node.props.height
	}
	if rect.width == 0 {
		rect.width = ctx.viewport.width
	}
	if rect.height == 0 {
		rect.height = ctx.viewport.height
	}

	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_fg_color(s.foreground.r, s.foreground.g, s.foreground.b)

	if rect.width > 1 && rect.height > 1 {
		// corners
		ctx.tui.draw_text(rect.x, rect.y, '+')
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y, '+')
		ctx.tui.draw_text(rect.x, rect.y + rect.height - 1, '+')
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + rect.height - 1, '+')
		// top/bottom
		for dx := 1; dx < rect.width - 1; dx++ {
			ctx.tui.draw_text(rect.x + dx, rect.y, '-')
			ctx.tui.draw_text(rect.x + dx, rect.y + rect.height - 1, '-')
		}
		// left/right
		for dy := 1; dy < rect.height - 1; dy++ {
			ctx.tui.draw_text(rect.x, rect.y + dy, '|')
			ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + dy, '|')
		}
	}

	mut combined := rect
	for child in node.children {
		child_rect := child.render(child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}

pub fn border_box(spec NodeSpec) VNode {
	return VNode{
		render:   render_border_box
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// TEXT: draws a line of text, grows parent by its rect (unless you want otherwise).
fn render_text(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top

	mut w := node.props.width
	if w == 0 {
		w = node.props.text.len
	}
	mut h := node.props.height
	if h == 0 {
		h = 1
	}

	rect := TermRect{
		x:      x
		y:      y
		width:  w
		height: h
	}

	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_fg_color(s.foreground.r, s.foreground.g, s.foreground.b)
	ctx.tui.draw_text(rect.x, rect.y, node.props.text)

	return rect
}

pub fn text(spec NodeSpec) VNode {
	return VNode{
		render:   render_text
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// HORIZONTAL layout: lays out children left→right, returns union, optionally registers itself.
fn render_horizontal(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut x := origin_x + node.props.left
	mut y := origin_y + node.props.top
	mut combined := TermRect{
		x:      x
		y:      y
		width:  0
		height: 0
	}

	for child in node.children {
		child_rect := child.render(child, x, y, mut ctx)
		combined = union_rect(combined, child_rect)
		x = child_rect.x + child_rect.width
	}

	// If you want horizontal container itself to receive events, register it:
	if node.events.click != none || node.events.mouse_move != none || node.events.mouse_down != none
		|| node.events.mouse_up != none || node.events.key_down != none
		|| node.events.key_up != none || node.events.focus != none || node.events.blur != none {
		_ = ctx.register(combined, node.style, node.events)
	}

	return combined
}

pub fn horizontal(spec NodeSpec) VNode {
	return VNode{
		render:   render_horizontal
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// VERTICAL layout: children top→bottom.
fn render_vertical(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut x := origin_x + node.props.left
	mut y := origin_y + node.props.top
	mut combined := TermRect{
		x:      x
		y:      y
		width:  0
		height: 0
	}

	for child in node.children {
		child_rect := child.render(child, x, y, mut ctx)
		combined = union_rect(combined, child_rect)
		y = child_rect.y + child_rect.height
	}

	if node.events.click != none || node.events.mouse_move != none || node.events.mouse_down != none
		|| node.events.mouse_up != none || node.events.key_down != none
		|| node.events.key_up != none || node.events.focus != none || node.events.blur != none {
		_ = ctx.register(combined, node.style, node.events)
	}

	return combined
}

pub fn vertical(spec NodeSpec) VNode {
	return VNode{
		render:   render_vertical
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// HLINE: length from props.width, does NOT grow parent box.
fn render_hline(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top
	mut len := node.props.width
	if len <= 0 {
		len = 1
	}
	rect := TermRect{
		x:      x
		y:      y
		width:  len
		height: 1
	}
	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_fg_color(s.foreground.r, s.foreground.g, s.foreground.b)
	for dx := 0; dx < rect.width; dx++ {
		ctx.tui.draw_text(rect.x + dx, rect.y, '-')
	}

	// does not grow parent: return empty rect
	return TermRect{}
}

pub fn hline(spec NodeSpec) VNode {
	return VNode{
		render:   render_hline
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: []VNode{}
	}
}

// VLINE: length from props.height, does NOT grow parent box.
fn render_vline(node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top
	mut len := node.props.height
	if len <= 0 {
		len = 1
	}
	rect := TermRect{
		x:      x
		y:      y
		width:  1
		height: len
	}
	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_fg_color(s.foreground.r, s.foreground.g, s.foreground.b)
	for dy := 0; dy < rect.height; dy++ {
		ctx.tui.draw_text(rect.x, rect.y + dy, '|')
	}

	return TermRect{}
}

pub fn vline(spec NodeSpec) VNode {
	return VNode{
		render:   render_vline
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: []VNode{}
	}
}

// Scrollbox etc. are just more VNodes with their own render functions that choose
// which children to call based on scroll state.

// --------------------- Root view type ---------------------

pub type RootViewFn = fn () VNode

// --------------------- Internal app + renderer ---------------------

struct App {
mut:
	tui      &tui.Context = unsafe { nil }
	root_fn  RootViewFn
	renderer Renderer
}

struct FocusState {
mut:
	path []int // ids from RenderedNode
}

struct Renderer {
mut:
	app        &App
	ctx        RenderContext
	last_key   KeyState
	last_mouse MouseState
	focus      FocusState
}

// ---------- Renderer: frame ----------

fn new_renderer(app &App) Renderer {
	return Renderer{
		app:        app
		ctx:        RenderContext{}
		last_key:   KeyState{}
		last_mouse: MouseState{}
		focus:      FocusState{}
	}
}

fn (mut r Renderer) render_frame() {
	// adapt field names to your term.ui
	width := r.app.tui.window_width
	height := r.app.tui.window_height

	r.app.tui.clear()

	r.ctx.tui = r.app.tui
	r.ctx.viewport = TermRect{
		x:      0
		y:      0
		width:  width
		height: height
	}
	r.ctx.nodes.clear()

	root := r.app.root_fn()
	_ = root.render(root, 0, 0, mut r.ctx)

	r.app.tui.flush()
}

// ---------- Renderer: event handling ----------

fn (mut r Renderer) handle_tui_event(e &tui.Event) {
	r.update_raw_input(e)
	kind := r.map_event_kind(e)
	if kind in [.mouse_move, .mouse_down, .mouse_up, .click] {
		r.handle_mouse_event(kind)
	} else if kind in [.key_down, .key_up] {
		r.handle_key_event(kind)
	}
}

fn (mut r Renderer) handle_mouse_event(kind UiEventKind) {
	x := r.last_mouse.x
	y := r.last_mouse.y

	path := r.hit_path(x, y) // outer -> inner
	if path.len == 0 {
		return
	}
	target := path[path.len - 1]

	if kind == .mouse_down || kind == .click {
		r.update_focus(path)
	}

	mut ev := UiEvent{
		kind:      kind
		target:    target
		path:      path
		key:       r.last_key
		mouse:     r.last_mouse
		propagate: true
	}
	r.dispatch_event(mut ev, path)
}

fn (mut r Renderer) handle_key_event(kind UiEventKind) {
	if r.focus.path.len == 0 {
		return
	}
	target := r.focus.path[r.focus.path.len - 1]

	mut ev := UiEvent{
		kind:      kind
		target:    target
		path:      r.focus.path.clone()
		key:       r.last_key
		mouse:     r.last_mouse
		propagate: true
	}
	r.dispatch_event(mut ev, r.focus.path.clone())
}

struct Hit {
	id   int
	area int
}

// hit-path from flattened nodes only; parents hit by area containment
fn (r &Renderer) hit_path(x int, y int) []int {
	mut hits := []Hit{}
	for n in r.ctx.nodes {
		if x >= n.rect.x && x < n.rect.x + n.rect.width && y >= n.rect.y
			&& y < n.rect.y + n.rect.height {
			area := n.rect.width * n.rect.height
			hits << Hit{
				id:   n.id
				area: area
			}
		}
	}
	hits.sort(a.area < b.area) // smallest area first

	// want outer -> inner: largest area last → reverse
	mut path := []int{}
	for i := hits.len - 1; i >= 0; i-- {
		path << hits[i].id
	}
	return path
}

fn (mut r Renderer) update_focus(new_path []int) {
	old_path := r.focus.path
	if new_path.len == 0 && old_path.len == 0 {
		return
	}
	k := common_prefix_len_ids(old_path, new_path)

	// blur old
	for i := old_path.len - 1; i >= k; i-- {
		id := old_path[i]
		node := r.node_by_id(id) or { continue }
		if node.events.blur != none {
			mut ev := UiEvent{
				kind:      .blur
				target:    id
				path:      old_path[..i + 1]
				key:       r.last_key
				mouse:     r.last_mouse
				propagate: true
			}
			// (node.events.blur or { UiEventHandler(nop_handler) })
			mut ev
		}
	}

	// focus new
	for i := k; i < new_path.len; i++ {
		id := new_path[i]
		node := r.node_by_id(id) or { continue }
		if node.events.focus != none {
			mut ev := UiEvent{
				kind:      .focus
				target:    id
				path:      new_path[..i + 1]
				key:       r.last_key
				mouse:     r.last_mouse
				propagate: true
			}
			(node.events.focus or { UiEventHandler(nop_handler) })
			mut ev
		}
	}

	r.focus.path = new_path.clone()
}

fn common_prefix_len_ids(a []int, b []int) int {
	mut n := if a.len < b.len { a.len } else { b.len }
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			return i
		}
	}
	return n
}

fn nop_handler(mut _ UiEvent) {}

fn (r &Renderer) node_by_id(id int) ?RenderedNode {
	if id < 0 || id >= r.ctx.nodes.len {
		return none
	}
	return r.ctx.nodes[id]
}

fn (mut r Renderer) dispatch_event(mut e UiEvent, path []int) {
	for i := path.len - 1; i >= 0 && e.propagate; i-- {
		id := path[i]
		node := r.node_by_id(id) or { continue }
		r.dispatch_to_node(mut e, node)
	}
}

fn (r &Renderer) dispatch_to_node(mut e UiEvent, node RenderedNode) {
	match e.kind {
		.click {
			if node.events.click != none {
				(node.events.click or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		.mouse_move {
			if node.events.mouse_move != none {
				(node.events.mouse_move or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		.mouse_down {
			if node.events.mouse_down != none {
				(node.events.mouse_down or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		.mouse_up {
			if node.events.mouse_up != none {
				(node.events.mouse_up or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		.key_down {
			if node.events.key_down != none {
				(node.events.key_down or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		.key_up {
			if node.events.key_up != none {
				(node.events.key_up or { UiEventHandler(nop_handler) })
				mut e
			}
		}
		else {}
	}
}

// ---------- raw input mapping ----------

fn (mut r Renderer) update_raw_input(e &tui.Event) {
	match e.typ {
		.key_down, .key_up {
			r.last_key.code = u32(e.code)
			r.last_key.char = e.ch
		}
		.mouse_move, .mouse_down, .mouse_up {
			r.last_mouse.x = e.x
			r.last_mouse.y = e.y
		}
		else {}
	}
}

fn (r &Renderer) map_event_kind(e &tui.Event) UiEventKind {
	// adjust to your term.ui enums
	match e.typ {
		.key_down { return .key_down }
		.key_up { return .key_up }
		.mouse_move { return .mouse_move }
		.mouse_down { return .mouse_down }
		.mouse_up { return .mouse_up }
		else { return .mouse_move }
	}
}

// ---------- term.ui callbacks (internal) ----------

fn event(e &tui.Event, user_data voidptr) {
	mut app := unsafe { &App(user_data) }
	app.renderer.handle_tui_event(e)
}

fn frame(user_data voidptr) {
	mut app := unsafe { &App(user_data) }
	app.renderer.render_frame()
}

// --------------------- Public Reactive API ---------------------

pub struct Reactive {
mut:
	app &App
}

pub fn reactive_app(root RootViewFn) &Reactive {
	mut app := &App{
		root_fn: root
	}
	app.renderer = new_renderer(app)
	app.tui = tui.init(
		user_data:      app
		event_fn:       event
		frame_fn:       frame
		hide_cursor:    true
		capture_events: true
	)
	return &Reactive{
		app: app
	}
}

pub fn (mut r Reactive) run() ! {
	r.app.tui.run()!
}
