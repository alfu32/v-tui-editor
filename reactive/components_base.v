module reactive

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
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
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
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)

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
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
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
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
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
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
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
