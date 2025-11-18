module reactive

import term.ui as tui
import os
import time
import arrays

// Type alias for glyph set identifiers used in stylesheets.
pub type GlyphSet = string
pub type GlyphSetName = string

// Optional: if you want to alias the map type too.
pub type GlyphSetMap = map[string]string

// All glyph sets.
// Boxes: 8 chars, indices 0..7
// Lines: 3 chars, indices 0..2
	pub const glyph_sets = {
		// boxes
		'empty':                '        '
		'box_light_straight':   '┌─┐│┘─└│'
		'box_heavy_straight':   '┏━┓┃┛━┗┃'
		'box_double_straight':  '╔═╗║╝═╚║'
		'box_light_rounded':    '╭─╮│╯─╰│'

		// lines (─)
		'line_simple_simple':    '├─┤┬│┴'
		'line_double_simple':    '╟─╢╤│╧'
		'line_double_double':    '╠═╣╦║╩'
	}

// Get the rune at `index` in the named glyph set.
// Returns '?' if the set or index is invalid.
pub fn get_symbol(set_name GlyphSetName, index int) string {
	s := glyph_sets[set_name] or {
		return '?'
	}
	rs := s.runes()
	if index < 0 || index >= rs.len {
		return '?'
	}
	return rs[index].str()
}

// --------------------- Geometry & styling ---------------------

pub struct TermPoint {
	pub mut:
	x      int
	y      int
}
pub struct TermRect {
pub mut:
	x      int
	y      int
	width  int
	height int
}

pub fn (r TermRect) copy() TermRect {
	return TermRect{
		x:      r.x
		y:      r.y
		width:  r.width
		height: r.height
	}
}

pub fn (r TermRect) contains_point(p TermPoint) bool {
	return r.x <= p.x && p.x <= (r.x+r.width) &&
		r.y <= p.y && p.y <= (r.y+r.height)
}

pub fn (r TermRect) is_empty() bool {
	return r.width == 0 && r.height == 0
}

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
pub fn (tc TermColor) copy() TermColor{
	return TermColor{
		r: tc.r
		g: tc.g
		b: tc.b
	}
}
fn lighteru8(a u8,value u8) u8 {
	rma := f64(255-a)
	add:=rma*f64(value)/f64(100)
	return u8(a+add)
}
fn darkeru8(a u8,value u8) u8 {
	rma := f64(a)
	sub:=rma*f64(value)/f64(100)
	return u8(a-sub)
}
pub fn (tc TermColor) lighter(value u8) TermColor{
	return TermColor{
		r: lighteru8(tc.r,value)
		g: lighteru8(tc.g,value)
		b: lighteru8(tc.b,value)
	}
}
pub fn (tc TermColor) darker(value u8) TermColor{
	return TermColor{
		r: darkeru8(tc.r,value)
		g: darkeru8(tc.g,value)
		b: darkeru8(tc.b,value)
	}
}

pub struct TermStyleState {
pub:
	background TermColor
	foreground TermColor
	border string = 'box_light_rounded'
	line string = 'line_simple_simple'
}

pub fn (tss TermStyleState) copy() TermStyleState{
	return TermStyleState{
		background: tss.background.copy()
		foreground: tss.foreground.copy()
		border: tss.border+""
		line: tss.line+""
	}
}

pub struct TermStyleSpec {
pub:
	default TermStyleState
	hover   ?TermStyleState
    focus   ?TermStyleState
}
pub fn (tss TermStyleSpec) copy() TermStyleSpec{
	return TermStyleSpec{
		default: tss.default.copy()
		hover: tss.hover or {tss.default}.copy()
		focus: tss.focus or {tss.default}.copy()
	}
}

pub fn make_stylesheet(base_spec TermStyleState) TermStyleSpec {
	return TermStyleSpec{
		default: TermStyleState{
			background: base_spec.background
			foreground: base_spec.foreground.darker(30)
			border: base_spec.border
			line: base_spec.line
		}
		hover:   TermStyleState{
			background: base_spec.background.lighter(30)
			foreground: base_spec.foreground.lighter(30)
			border: base_spec.border
			line: base_spec.line
		}
		focus:   TermStyleState{
			background: base_spec.background
			foreground: base_spec.foreground.darker(10)
			border: base_spec.border
			line: base_spec.line
		}
	}
}
pub fn default_box_style() TermStyleSpec {
	return make_stylesheet(
			background: TermColor{32, 32, 32}
			foreground: TermColor{192, 192, 192}
			border: 'box_light_rounded'
			line: 'line_simple_simple'
	)
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
	num   u32
	char  rune
	ctrl  bool
	alt   bool
	shift bool
	meta  bool
}
pub fn (ks KeyState) str() string {
	mut mods:=0
	if ks.shift {mods|=8}
	if ks.ctrl {mods|=4}
	if ks.meta {mods|=2}
	if ks.alt {mods|=1}
	return "KeyState{code:0x${ks.code:02X},num:0x${ks.num:02X},char:${ks.char},mods:b${mods:04b}}"
}

pub struct MouseButtons {
	pub mut:
	left   bool
	middle bool
	right  bool
}
pub fn (mb MouseButtons) str() string {
	mut mods:=0
	if mb.left {mods|=4}
	if mb.middle {mods|=2}
	if mb.right {mods|=1}
	return "MouseButtons{b${mods:03b}}"
}

pub struct MouseState {
pub mut:
	x       int
	y       int
	buttons MouseButtons
	wheel   int
}
pub fn (ms MouseState) str() string {
	return "MouseState{x:${ms.x},y:${ms.y},buttons:${ms.buttons},wheel:${ms.wheel}}"
}

pub struct UiEvent {
pub mut:
	kind        UiEventKind
	target      int
	path        []int
	key         KeyState
	mouse       MouseState
	renderer        Renderer
	propagate   bool = true
}
pub fn (ev UiEvent) str() string {
	return "
	UiEvent{
	kind:${ev.kind}, target:${ev.target}, path:${ev.path},
	key:${ev.key},
	mouse:${ev.mouse},
	renderer:[Circular], propagate:${ev.propagate} }
	".trim_indent()
}

pub type UiEventHandler = fn (mut UiEvent)

pub struct EventSpec {
pub mut:
	is_key       bool
	is_mouse     bool
	key_char     ?rune  // e.g. 'c' for "Ctrl-C"
	mouse_action string // "click", "down", "up", "move", "wheel" or ""
	req_ctrl     bool
	req_alt      bool
	req_shift    bool
	req_meta     bool
}

// ----------------- parsing -----------------

fn parse_event_spec(pattern string) EventSpec {
	mut spec := EventSpec{}
	tokens := pattern.to_lower().split('-')

	for t in tokens {
		match t {
			'ctrl' {
				spec.req_ctrl = true
			}
			'alt' {
				spec.req_alt = true
			}
			'shift' {
				spec.req_shift = true
			}
			'meta', 'cmd', 'super' {
				spec.req_meta = true
			}
			'click', 'down', 'up', 'move', 'wheel' {
				spec.is_mouse = true
				spec.mouse_action = t
			}
			else {
				// assume it's a key identifier: simple case, first rune
				if t.len > 0 {
					r := t.runes()[0]
					spec.key_char = r
					spec.is_key = true
				}
			}
		}
	}

	// if neither key nor mouse explicitly detected, default to key
	if !spec.is_key && !spec.is_mouse {
		spec.is_key = true
	}

	return spec
}

// Public factory: wrap `handler` with a filter described by `pattern`.
pub fn on(pattern string, handler UiEventHandler) UiEventHandler {
	spec := parse_event_spec(pattern)
	return fn [spec, handler] (mut e UiEvent) {
		if spec.matches(e) {
			handler(mut e)
		}
	}
}

// ----------------- matching -----------------

fn (spec &EventSpec) matches(e UiEvent) bool {
	// Modifiers: "at least" semantics: if required, must be true.
	if spec.req_ctrl && !e.key.ctrl {
		return false
	}
	if spec.req_alt && !e.key.alt {
		return false
	}
	if spec.req_shift && !e.key.shift {
		return false
	}
	if spec.req_meta && !e.key.meta {
		return false
	}

	if spec.is_key {
		return spec.matches_key(e)
	}
	if spec.is_mouse {
		return spec.matches_mouse(e)
	}
	return false
}

fn (spec &EventSpec) matches_key(e UiEvent) bool {
	// Only react on key_down; change if you want both up/down
	if e.kind != .key_down {
		return false
	}
	kc := spec.key_char or { return false }

	// case-insensitive compare
	ev_ch := e.key.char.str().to_lower()
	want_ch := [kc].str().to_lower()
	if ev_ch != want_ch {
		return false
	}
	return true
}

fn (spec &EventSpec) matches_mouse(e UiEvent) bool {
	// Map high-level mouse actions onto your UiEventKind
	match spec.mouse_action {
		'click' {
			// if you don’t synthesize .click, map to .mouse_down or .mouse_up
			if e.kind != .mouse_down {
				return false
			}
		}
		'down' {
			if e.kind != .mouse_down {
				return false
			}
		}
		'up' {
			if e.kind != .mouse_up {
				return false
			}
		}
		'move' {
			if e.kind != .mouse_move {
				return false
			}
		}
		'wheel' {
			// you might have a dedicated UiEventKind for this later;
			// for now assume wheel shows up as mouse_move with non-zero wheel
			if e.mouse.wheel == 0 {
				return false
			}
		}
		else {
			// generic mouse combo: accept any mouse event
			if e.kind !in [.mouse_move, .mouse_down, .mouse_up] {
				return false
			}
		}
	}
	return true
}

// --------------------- Rendered nodes for events ---------------------

pub struct RenderedNode {
pub:
	id     int
	rect   TermRect
	style  TermStyleSpec
	events []UiEventHandler
}

pub fn (node RenderedNode) dispatch_event(mut ev UiEvent) {
	for event_handler in node.events {
		event_handler(mut ev)
	}
}

pub struct RenderContext {
pub mut:
	tui      &tui.Context = unsafe { nil }
	viewport TermRect
	nodes    []RenderedNode
	mouse       MouseState    // last mouse position
	messages []string
}
pub fn (mut ctx RenderContext) dump_messages_to_file(filename string)  ! {
	os.write_lines(filename, ctx.messages)!
}
pub fn (mut ctx RenderContext) log(message string,file_file string) {
	tm:=time.now()
	ctx.messages << "${tm} [${file_file.replace('/home/devlin/Development/','')}] ${message}"
	ctx.dump_messages_to_file("log.log") or {}
}


pub fn (mut ctx RenderContext) register(rect TermRect, style TermStyleSpec, events []UiEventHandler) int {
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

pub type RenderFn = fn (mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect

pub struct VNode {
pub mut:
	constructor string
	tag         string
	render      RenderFn = unsafe { nil }
	props       TermProps
	style       TermStyleSpec
	events      []UiEventHandler
	children    []VNode
	has_focus 	bool
}

pub struct NodeSpec {
pub:
	tag 	 string
	props    TermProps        = TermProps{}
	style    TermStyleSpec    = default_box_style()
	events   []UiEventHandler = []UiEventHandler{}
	children []VNode          = []VNode{}
}

// --------------------- Root view type ---------------------

pub type RootViewFn = fn () VNode

// --------------------- Internal app + renderer ---------------------

@[heap]
struct App {
mut:
	tui            &tui.Context = unsafe { nil }
	root_fn        RootViewFn   = unsafe { nil }
	renderer       &Renderer    = unsafe { nil }
	counter        int
	exit_code      int
	exit_next_loop bool
}

pub fn (mut a App) will_exit(code int) {
	a.exit_code = code
	a.exit_next_loop = true
}

struct FocusState {
mut:
	path []int
}

@[heap]
pub struct Renderer {
pub mut:
	app        &App = unsafe { nil }
	ctx        RenderContext
	last_key   KeyState
	last_mouse MouseState
	focus      FocusState
}

// ---------- Renderer: frame ----------

fn new_renderer(app &App) &Renderer {
	return &Renderer{
		app:        app
		ctx:        RenderContext{}
		last_key:   KeyState{}
		last_mouse: MouseState{}
		focus:      FocusState{}
	}
}

fn (mut r Renderer) render_frame() {
	width := r.app.tui.window_width
	height := r.app.tui.window_height
	r.ctx.mouse = r.last_mouse

	r.app.tui.clear()

	r.ctx.tui = r.app.tui
	r.ctx.viewport = TermRect{
		x:      0
		y:      0
		width:  width
		height: height
	}
	r.ctx.nodes.clear()

	mut root := r.app.root_fn()

	// 1) register root as a full-viewport node
	root_id := r.ctx.register(
		r.ctx.viewport,
		default_box_style(),
		root.events, // or root.style + handlers, depending on your RenderedNode
	)
	_ = root_id
	r.ctx.log('registered root_id ${root_id}',@LOCATION)

	_ = root.render(mut root, 0, 0, mut r.ctx)

	r.app.tui.flush()
}

// ---------- Renderer: event handling ----------

fn (mut r Renderer) handle_tui_event(e &tui.Event) {
	r.update_raw_input(e)
	kind := r.map_event_kind(e)
	if kind in [.mouse_move, .mouse_down, .mouse_up, .click] {
		// r.ctx.log('handle mouse event ${kind}',@LOCATION)
		r.handle_mouse_event(kind)
	} else if kind in [.key_down, .key_up] {
		r.ctx.log('handle key event ${kind}',@LOCATION)
		r.handle_key_event(kind)
	}
}

fn (mut r Renderer) handle_mouse_event(kind UiEventKind) {
	x := r.last_mouse.x
	y := r.last_mouse.y

	path := r.hit_path(x, y)
	if path.len == 0 {
		return
	}
	r.focus.path = path
	target := path[path.len - 1]

	if kind == .mouse_down || kind == .click || kind == .mouse_move {
		r.update_focus(path)
	}

	mut ev := UiEvent{
		kind:        kind
		target:      target
		path:        path.clone()
		key:         r.last_key
		mouse:       r.last_mouse
		renderer: 		 r
		propagate:   true
	}
	r.dispatch_event(mut ev, path)
}

fn (mut r Renderer) handle_key_event(kind UiEventKind) {
	r.ctx.log('handling key event ${kind}',@LOCATION)
	r.ctx.log('handling key event focus path ${r.focus.path}',@LOCATION)
	if r.focus.path.len == 0 {
		r.ctx.log('handling key event no target ?!',@LOCATION)
		return
	}
	r.ctx.log('handling key event proceeding',@LOCATION)
	target := r.focus.path[r.focus.path.len - 1]

	mut ev := UiEvent{
		kind:        kind
		target:      target
		path:        r.focus.path.clone()
		renderer:    r
		key:         r.last_key
		mouse:       r.last_mouse
		propagate:   true
	}
	r.ctx.log('dispatching key event ${ev}',@LOCATION)
	r.dispatch_event(mut ev, r.focus.path.clone())
}

struct Hit {
	id   int
	area int
}

// hit-path from flattened nodes only; parents hit by area containment
fn (mut r Renderer) hit_path(x int, y int) []int {
	mut hits := []Hit{}
	for n in r.ctx.nodes {
		if x >= n.rect.x && x < n.rect.x + n.rect.width && y >= n.rect.y
			&& y < n.rect.y + n.rect.height/* || n.id == 0 */{
			mut area := n.rect.width * n.rect.height
			// if n.id == 0 {
			// 	area = r.ctx.viewport.width * r.ctx.viewport.width
			// 	// r.ctx.log('added root to hit path with area ${area}',@LOCATION)
			// }
			hits << Hit{
				id:   n.id
				area: area
			}
		}
	}
	hits.sort(a.area < b.area)

	mut path := []int{}
	for i := hits.len - 1; i >= 0; i-- {
		path << hits[i].id
	}
	return path
}
fn ident[T](t int) string {
	return "$t"
}
fn (mut r Renderer) update_focus(new_path []int) {
	old_path := r.focus.path
	if new_path.len == 0 && old_path.len == 0 {
		return
	}
	if arrays.join_to_string(new_path,(","),ident[int]) == arrays.join_to_string(old_path,(","),ident[int]) {
		return
	}
	k := common_prefix_len_ids(old_path, new_path)

	// blur old
	r.ctx.log("bluring ${old_path}",@LOCATION)
	for i := old_path.len - 1; i >= k; i-- {
		id := old_path[i]
		node := r.node_by_id(id) or { continue }
		mut blur_event := UiEvent{
			kind:        .blur
			target:      id
			path:        old_path[..i + 1].clone()
			key:         r.last_key
			mouse:       r.last_mouse
			renderer: r
			propagate:   true
		}
		node.dispatch_event(mut blur_event)
	}

	// focus new
	r.ctx.log("focusing ${new_path}",@LOCATION)
	for i := k; i < new_path.len; i++ {
		id := new_path[i]
		node := r.node_by_id(id) or { continue }
		mut focus_event := UiEvent{
			kind:        .focus
			target:      id
			path:        new_path[..i + 1].clone()
			key:         r.last_key
			mouse:       r.last_mouse
			renderer: r
			propagate:   true
		}
		node.dispatch_event(mut focus_event)
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
		node.dispatch_event(mut e)
		// for handler in node.events {
		// 	handler(mut e)
		// 	// if !e.propagate {
		// 	// 	break
		// 	// }
		// }
	}
}

// ---------- raw input mapping ----------

fn (mut r Renderer) update_raw_input(e &tui.Event) {
	r.last_key.code = u32(e.code)
	r.last_key.char = rune(e.ascii)
	r.last_key.ctrl = e.modifiers.has(.ctrl)
	r.last_key.shift = e.modifiers.has(.shift)
	r.last_key.alt = e.modifiers.has(.alt)
	r.last_mouse.x = e.x
	r.last_mouse.y = e.y
	r.last_mouse.buttons.left = e.button == .left
	r.last_mouse.buttons.right = e.button == .right
	r.last_mouse.buttons.middle = e.button == .middle
	// r.ctx.viewport.width = e.width
	// r.ctx.viewport.height = e.height
	if e.direction == .up {
		r.last_mouse.wheel = 1
	} else if e.direction == .down {
		r.last_mouse.wheel = -1
	} else {
		r.last_mouse.wheel = 0
	}
	// r.ctx.log('event ${e.typ} ${r.last_key}  ${r.last_mouse}',@LOCATION)
	match e.typ {
		.mouse_move, .mouse_down, .mouse_up, .mouse_drag {
			r.last_mouse.x = e.x
			r.last_mouse.y = e.y
			r.last_mouse.buttons.left = e.button == .left
			r.last_mouse.buttons.right = e.button == .right
			r.last_mouse.buttons.middle = e.button == .middle
			// r.ctx.log('mouse button event ${r.last_mouse}',@LOCATION)
		}
		.mouse_scroll {
			if e.direction == .up {
				r.last_mouse.wheel = 1
			} else if e.direction == .down {
				r.last_mouse.wheel = -1
			} else {
				r.last_mouse.wheel = 0
			}
			r.ctx.log('mouse scroll event ${r.last_mouse}',@LOCATION)
		}
		.resized {
			// keep viewport in sync if you want; render_frame will set it again anyway
			r.ctx.viewport.width = e.width
			r.ctx.viewport.height = e.height
			r.ctx.log('window resize event ${r.ctx.viewport}',@LOCATION)
		}
		else {}
	}
}

fn (r &Renderer) map_event_kind(e &tui.Event) UiEventKind {
	return match e.typ {
		.key_down { .key_down }
		.mouse_move, .mouse_drag, .mouse_scroll { .mouse_move }
		.mouse_down { .mouse_down }
		.mouse_up { .mouse_up }
		.resized, .unknown { .mouse_move }
	}
}

// ---------- term.ui callbacks (internal) ----------

fn event_loop_function(e &tui.Event, user_data voidptr) {
	mut app := unsafe { &App(user_data) }
	if e.typ == .key_down && e.code == .r && e.modifiers.has(.ctrl) && e.modifiers.has(.shift) {
		app.renderer.ctx.dump_messages_to_file('direct-exit.log') or {}
		app.will_exit(0)
	}
	if app.exit_next_loop {
		app.renderer.ctx.dump_messages_to_file('final-exit.log') or {}
		exit(app.exit_code)
	}
	app.renderer.handle_tui_event(e)
}

fn frame_loop_function(user_data voidptr) {
	mut app := unsafe { &App(user_data) }
	app.counter += 1
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
		event_fn:       event_loop_function
		frame_fn:       frame_loop_function
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
