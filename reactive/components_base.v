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
fn render_box(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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

	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_rect(rect.x,rect.y,rect.x+rect.width,rect.y+rect.height)
	ctx.tui.reset()
	// for dy := 0; dy < rect.height; dy++ {
	// 	for dx := 0; dx < rect.width; dx++ {
	// 		ctx.tui.draw_text(rect.x + dx, rect.y + dy, ' ')
	// 	}
	// }

	mut combined := rect
	for mut child in node.children {
		// child.has_focus=has_focus
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}

pub fn box(spec NodeSpec) VNode {
	return VNode{
		constructor: "box"
		tag: 	  spec.tag
		render:   render_box
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// BORDER BOX: border only, grows parent, children inside.
fn render_button(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_rect(rect.x,rect.y,rect.x+rect.width-1,rect.y+rect.height-1)

	if rect.width > 1 && rect.height > 1 {
		// corners
		ctx.tui.draw_text(rect.x, rect.y, get_symbol(s.border,0))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y, get_symbol(s.border,2))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + rect.height - 1, get_symbol(s.border,4))
		ctx.tui.draw_text(rect.x, rect.y + rect.height - 1, get_symbol(s.border,6))
		// top/bottom
		for dx := 1; dx < rect.width - 1; dx++ {
			ctx.tui.draw_text(rect.x + dx, rect.y, get_symbol(s.border,1))
			ctx.tui.draw_text(rect.x + dx, rect.y + rect.height - 1, get_symbol(s.border,5))
		}
		// left/right
		for dy := 1; dy < rect.height - 1; dy++ {
			ctx.tui.draw_text(rect.x, rect.y + dy, get_symbol(s.border,7))
			ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + dy, get_symbol(s.border,3))
		}
	}
	ctx.tui.reset()

	mut combined := rect
	for mut child in node.children {
		child.has_focus=has_focus
		child.style=node.style.copy()
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}

pub fn button(spec NodeSpec) VNode {
	return VNode{
		constructor: "button"
		tag: 	  spec.tag
		render:   render_button
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// BORDER BOX: border only, grows parent, children inside.
fn render_border_box(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_rect(rect.x,rect.y,rect.x+rect.width-1,rect.y+rect.height-1)

	if rect.width > 1 && rect.height > 1 {
		// corners
		ctx.tui.draw_text(rect.x, rect.y, get_symbol(s.border,0))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y, get_symbol(s.border,2))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + rect.height - 1, get_symbol(s.border,4))
		ctx.tui.draw_text(rect.x, rect.y + rect.height - 1, get_symbol(s.border,6))
		// top/bottom
		for dx := 1; dx < rect.width - 1; dx++ {
			ctx.tui.draw_text(rect.x + dx, rect.y, get_symbol(s.border,1))
			ctx.tui.draw_text(rect.x + dx, rect.y + rect.height - 1, get_symbol(s.border,5))
		}
		// left/right
		for dy := 1; dy < rect.height - 1; dy++ {
			ctx.tui.draw_text(rect.x, rect.y + dy, get_symbol(s.border,7))
			ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + dy, get_symbol(s.border,3))
		}
	}
	ctx.tui.reset()

	mut combined := rect
	for mut child in node.children {
		// child.has_focus=has_focus
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}

pub fn border_box(spec NodeSpec) VNode {
	return VNode{
		constructor: "border_box"
		tag: 	  spec.tag
		render:   render_border_box
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}


// BORDER BOX: border only, grows parent, children inside.
fn render_container_border_box(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_rect(rect.x,rect.y,rect.x+rect.width-1,rect.y+rect.height-1)

	if rect.width > 1 && rect.height > 1 {
		// corners
		ctx.tui.draw_text(rect.x, rect.y, get_symbol(s.border,0))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y, get_symbol(s.border,2))
		ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + rect.height - 1, get_symbol(s.border,4))
		ctx.tui.draw_text(rect.x, rect.y + rect.height - 1, get_symbol(s.border,6))
		// top/bottom
		for dx := 1; dx < rect.width - 1; dx++ {
			ctx.tui.draw_text(rect.x + dx, rect.y, get_symbol(s.border,1))
			ctx.tui.draw_text(rect.x + dx, rect.y + rect.height - 1, get_symbol(s.border,5))
		}
		// left/right
		for dy := 1; dy < rect.height - 1; dy++ {
			ctx.tui.draw_text(rect.x, rect.y + dy, get_symbol(s.border,7))
			ctx.tui.draw_text(rect.x + rect.width - 1, rect.y + dy, get_symbol(s.border,3))
		}
	}

	ctx.tui.reset()

	mut combined := rect
	for mut child in node.children {
		child.has_focus=has_focus
		child.style=node.style.copy()
		child_rect := child.render(mut child, rect.x, rect.y, mut ctx)
		combined = union_rect(combined, child_rect)
	}
	return combined
}
pub struct BorderBoxNodeSpec{
	NodeSpec
	style_propagation string = 'overwrite'
}
pub fn container_border_box(spec BorderBoxNodeSpec) VNode {
	return VNode{
		constructor: "container_border_box"
		tag: 	  spec.tag
		render:   render_container_border_box
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// TEXT: draws a line of text, grows parent by its rect (unless you want otherwise).
fn render_text(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
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
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_text(rect.x, rect.y, node.props.text)
	ctx.tui.reset()

	return rect
}

pub fn text(spec NodeSpec) VNode {
	return VNode{
		constructor: "text"
		tag: 	  spec.tag
		render:   render_text
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// HORIZONTAL layout: lays out children left→right, returns union, optionally registers itself.
fn render_horizontal(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut x := origin_x + node.props.left
	mut y := origin_y + node.props.top
	mut combined := TermRect{
		x:      x
		y:      y
		width:  0
		height: 0
	}

	has_focus:=node.has_focus
	for mut child in node.children {
		child.has_focus=has_focus
		child_rect := child.render(mut child, x, y, mut ctx)
		combined = union_rect(combined, child_rect)
		x = child_rect.x + child_rect.width
	}

	// If you want horizontal container itself to receive events, register it:
	_ = ctx.register(combined, node.style, node.events)

	return combined
}

pub fn horizontal(spec NodeSpec) VNode {
	return VNode{
		constructor: "horizontal"
		tag: 	  spec.tag
		render:   render_horizontal
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// VERTICAL layout: children top→bottom.
fn render_vertical(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	mut x := origin_x + node.props.left
	mut y := origin_y + node.props.top
	mut combined := TermRect{
		x:      x
		y:      y
		width:  0
		height: 0
	}
	has_focus:=node.has_focus

	for mut child in node.children {
		child.has_focus=has_focus
		child_rect := child.render(mut child, x, y, mut ctx)
		combined = union_rect(combined, child_rect)
		y = child_rect.y + child_rect.height
	}
	_ = ctx.register(combined, node.style, node.events)

	return combined
}

pub fn vertical(spec NodeSpec) VNode {
	return VNode{
		constructor: "vertical"
		tag: 	  spec.tag
		render:   render_vertical
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: spec.children
	}
}

// HLINE: length from props.width, does NOT grow parent box.
fn render_hline(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top
	mut len := node.props.width
	if len <= 0 {
		len = ctx.viewport.width
	}
	rect := TermRect{
		x:      x
		y:      y
		width:  len
		height: 1
	}
	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_text(rect.x, rect.y, get_symbol(s.line,0))
	for dx := 1; dx < rect.width-1; dx++ {
		ctx.tui.draw_text(rect.x + dx, rect.y, get_symbol(s.line,1))
	}
	ctx.tui.draw_text(rect.x + rect.width-1, rect.y, get_symbol(s.line,2))
	ctx.tui.reset()

	// does not grow parent: return empty rect
	return TermRect{}
}

pub fn hline(spec NodeSpec) VNode {
	return VNode{
		constructor: "hline"
		tag: 	  spec.tag
		render:   render_hline
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: []VNode{}
	}
}

// VLINE: length from props.height, does NOT grow parent box.
fn render_vline(mut node VNode, origin_x int, origin_y int, mut ctx RenderContext) TermRect {
	x := origin_x + node.props.left
	y := origin_y + node.props.top
	mut len := node.props.height
	if len <= 0 {
		len = ctx.viewport.height
	}
	rect := TermRect{
		x:      x
		y:      y
		width:  1
		height: len
	}
	_ = ctx.register(rect, node.style, node.events)

	mut s := node.style.default
	has_focus:=node.has_focus || rect.contains_point(x:ctx.mouse.x,y:ctx.mouse.y)
	if has_focus{
		s=node.style.focus or {node.style.default}
	}
	ctx.tui.set_bg_color(r: s.background.r, g: s.background.g, b: s.background.b)
	ctx.tui.set_color(r: s.foreground.r, g: s.foreground.g, b: s.foreground.b)
	ctx.tui.draw_text(rect.x, rect.y, get_symbol(s.line,3))
	for dy := 1; dy < rect.height-1; dy++ {
		ctx.tui.draw_text(rect.x, rect.y + dy, get_symbol(s.line,4))
	}
	ctx.tui.draw_text(rect.x, rect.y + rect.height-1, get_symbol(s.line,5))
	ctx.tui.reset()

	return TermRect{}
}

pub fn vline(spec NodeSpec) VNode {
	return VNode{
		constructor: "vline"
		tag: 	  spec.tag
		render:   render_vline
		props:    spec.props
		style:    spec.style
		events:   spec.events
		children: []VNode{}
	}
}

// Scrollbox etc. are just more VNodes with their own render functions that choose
// which children to call based on scroll state.
