module reactive

// Rect union helper used by containers.
fn union_rect(a TermRect, b TermRect) TermRect {
	if a.is_empty() {
		return b
	}
	if b.is_empty() {
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

// --------------------- Primitive components ---------------------

// RECT: fills a rectangle using the node style. Width/height of 0 fill the
// entire viewport (or whatever space the container provides via origin).
fn render_rect(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut rect := TermRect{
		x:      origin_x + node.props.left
		y:      origin_y + node.props.top
		width:  node.props.width
		height: node.props.height
	}
	if node.props.width == -1 {
		rect.width = ctx.viewport.width
	}
	if node.props.height == -1 {
		rect.height = ctx.viewport.height
	}
	if rect.width <= 0 {
		rect.width = if ctx.viewport.width > 0 { ctx.viewport.width } else { 1 }
	}
	if rect.height <= 0 {
		rect.height = 1
	}
	_ = ctx.register(rect, node.style, node.events, node.tag)

	mut style := node.style.default
	if rect.contains_point(x: ctx.mouse.x, y: ctx.mouse.y) {
		style = (node.style.focus or { node.style.default })
	}
	ctx.tui.set_bg_color(r: style.background.r, g: style.background.g, b: style.background.b)
	ctx.tui.set_color(r: style.foreground.r, g: style.foreground.g, b: style.foreground.b)
	ctx.tui.draw_rect(rect.x, rect.y, rect.x + rect.width, rect.y + rect.height)
	// ctx.tui.draw_text(rect.x, rect.y, "x:${rect.x},y:${rect.y}")
	ctx.tui.reset()

	saved_viewport := ctx.viewport
	ctx.viewport = rect
	mut combined := rect
	for mut child in node.children {
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	ctx.viewport = saved_viewport
	return combined
}

pub fn rect(spec NodeSpec) VNode {
	return VNode{
		constructor: 'rect'
		tag:         spec.tag
		render:      render_rect
		props:       spec.props
		style:       spec.style
		events:      spec.events
		children:    spec.children
	}
}

// TEXT: draws a string at the provided position.
fn render_text(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top

	mut width := node.props.width
	if width == 0 {
		width = node.props.text.len
	}
	mut height := node.props.height
	if height == 0 {
		height = 1
	}

	rect := TermRect{
		x:      x
		y:      y
		width:  width
		height: height
	}

	_ = ctx.register(rect, node.style, node.events, node.tag)

	mut style := node.style.default
	if rect.contains_point(x: ctx.mouse.x, y: ctx.mouse.y) {
		style = node.style.focus or { node.style.default }
	}
	ctx.tui.set_bg_color(r: style.background.r, g: style.background.g, b: style.background.b)
	ctx.tui.set_color(r: style.foreground.r, g: style.foreground.g, b: style.foreground.b)
	ctx.tui.draw_text(rect.x, rect.y, node.props.text)
	ctx.tui.reset()

	return rect
}

pub fn text(spec NodeSpec) VNode {
	return VNode{
		constructor: 'text'
		tag:         spec.tag
		render:      render_text
		props:       spec.props
		style:       spec.style
		events:      spec.events
		children:    spec.children
	}
}

// RELATIVE: layout container positioning children relative to its origin.
fn render_relative(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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

	_ = ctx.register(rect, node.style, node.events, node.tag)

	saved_viewport := ctx.viewport
	ctx.viewport = rect
	mut combined := rect
	for mut child in node.children {
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	ctx.viewport = saved_viewport
	return combined
}

pub fn relative(spec NodeSpec) VNode {
	return VNode{
		constructor: 'relative'
		tag:         spec.tag
		render:      render_relative
		props:       spec.props
		style:       spec.style
		events:      spec.events
		children:    spec.children
	}
}
