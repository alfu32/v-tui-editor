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
		x:      r.x
		y:      r.y
		width:  r.width
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
		x:      x1
		y:      y1
		width:  x2 - x1
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

// NOTE: now includes terminal size (current frame)
pub struct UiEvent {
pub mut:
	kind        UiEventKind
	target      int   // id in rendered node list
	path        []int // outer -> inner, ids
	key         KeyState
	mouse       MouseState
	term_width  int
	term_height int
	propagate   bool = true
}

pub type UiEventHandler = fn (mut UiEvent)

pub struct TermEventHandlers {
pub:
	click      ?UiEventHandler
	mouse_move ?UiEventHandler
	mouse_down ?UiEventHandler
	mouse_up   ?UiEventHandler
	key_down   ?UiEventHandler
	key_up     ?UiEventHandler
	focus      ?UiEventHandler
	blur       ?UiEventHandler
}

// --------------------- Rendered nodes for events ---------------------

pub struct RenderedNode {
pub:
	id     int
	rect   TermRect
	style  TermStyleSpec
	events TermEventHandlers
}

// Context passed down to *every* render() call
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
		kind:        kind
		target:      target
		path:        path
		key:         r.last_key
		mouse:       r.last_mouse
		term_width:  r.ctx.viewport.width
		term_height: r.ctx.viewport.height
		propagate:   true
	}
	r.dispatch_event(mut ev, path)
}

fn (mut r Renderer) handle_key_event(kind UiEventKind) {
	if r.focus.path.len == 0 {
		return
	}
	target := r.focus.path[r.focus.path.len - 1]

	mut ev := UiEvent{
		kind:        kind
		target:      target
		path:        r.focus.path.clone()
		key:         r.last_key
		mouse:       r.last_mouse
		term_width:  r.ctx.viewport.width
		term_height: r.ctx.viewport.height
		propagate:   true
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
	// sort by area ascending (inner = smaller area)
	hits.sort(a.area < b.area)

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
				kind:        .blur
				target:      id
				path:        old_path[..i + 1].clone()
				key:         r.last_key
				mouse:       r.last_mouse
				term_width:  r.ctx.viewport.width
				term_height: r.ctx.viewport.height
				propagate:   true
			}
			node.events.blur(mut ev)
		}
	}

	// focus new
	for i := k; i < new_path.len; i++ {
		id := new_path[i]
		node := r.node_by_id(id) or { continue }
		if node.events.focus != none {
			mut ev := UiEvent{
				kind:        .blur
				target:      id
				path:        old_path[..i + 1].clone()
				key:         r.last_key
				mouse:       r.last_mouse
				term_width:  r.ctx.viewport.width
				term_height: r.ctx.viewport.height
				propagate:   true
			}
			node.events.focus(mut ev)
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
			if handler := node.events.click {
				handler(mut e)
			}
		}
		.mouse_move {
			if handler := node.events.mouse_move {
				handler(mut e)
			}
		}
		.mouse_down {
			if handler := node.events.mouse_down {
				handler(mut e)
			}
		}
		.mouse_up {
			if handler := node.events.mouse_up {
				handler(mut e)
			}
		}
		.key_down {
			if handler := node.events.key_down {
				handler(mut e)
			}
		}
		.key_up {
			if handler := node.events.key_up {
				handler(mut e)
			}
		}
		else {}
	}
}

// ---------- raw input mapping ----------

fn (mut r Renderer) update_raw_input(e &tui.Event) {
	match e.typ {
		.key_down {
			r.last_key.code = u32(e.code)
			r.last_key.char = e.ascii
			// fill modifiers if term.ui exposes them
		}
		.mouse_move, .mouse_down, .mouse_up {
			r.last_mouse.x = e.x
			r.last_mouse.y = e.y
			// fill buttons if term.ui exposes them
		}
		else {}
	}
}

fn (r &Renderer) map_event_kind(e &tui.Event) UiEventKind {
	// adjust to your term.ui enums
	match e.typ {
		.key_down { return .key_down }
		// .key_up { return .key_up }
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
