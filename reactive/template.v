module reactive

import strconv
import strings

// TemplateContext carries the dynamic state that a markup based
// component needs at render time: simple string props, the children
// that should be slotted into `<slot/>`, and event handler bindings.
pub struct TemplateContext {
pub:
	props    map[string]string     = map[string]string{}
	handlers map[string]UiEventHandler = map[string]UiEventHandler{}
	children []VNode               = []VNode{}
}

// Template parser -----------------------------------------------------------

struct TemplateNode {
	name      string
	attrs     map[string]string
	children  []TemplateNode
	text      string
	is_text   bool
	self_close bool
}

struct TemplateParser {
	src string
	mut:
	idx int
}

fn new_template_parser(src string) TemplateParser {
	return TemplateParser{src: src}
}

fn (mut p TemplateParser) parse_all() ![]TemplateNode {
	mut nodes := []TemplateNode{}
	for {
		p.skip_whitespace()
		if p.eof() {
			break
		}
		if p.starts_with('</') {
			break
		}
		if p.peek() == `<` {
			nodes << p.parse_element()!
		} else {
			n := p.parse_text_node()
			if n.text.len > 0 {
				nodes << n
			}
		}
	}
	return nodes
}

fn (mut p TemplateParser) parse_element() !TemplateNode {
	p.expect(`<`)
	name := p.parse_identifier()
	mut attrs := map[string]string{}
	for {
		p.skip_whitespace()
		if p.eof() {
			return error('unterminated tag <${name}>')
		}
		ch := p.peek()
		if ch == `>` || ch == `/` {
			break
		}
		attr_name := p.parse_identifier()
		p.skip_whitespace()
		mut value := ''
		if p.peek() == `=` {
			p.idx++
			p.skip_whitespace()
			value = p.parse_attribute_value()
		}
		attrs[attr_name.to_lower()] = value
	}
	mut self_closing := false
	if p.peek() == `/` {
		self_closing = true
		p.idx++
	}
	p.expect(`>`)
	mut children := []TemplateNode{}
	if !self_closing {
		for {
			p.skip_whitespace()
			if p.starts_with('</') {
				// closing tag
				p.idx += 2
				closing := p.parse_identifier()
				if closing.to_lower() != name.to_lower() {
					return error('expected </${name}> but found </${closing}>')
				}
				p.skip_whitespace()
				p.expect(`>`)
				break
			}
			if p.eof() {
				return error('unterminated tag <${name}>')
			}
			if p.peek() == `<` {
				children << p.parse_element()!
			} else {
				n := p.parse_text_node()
				if n.text.len > 0 {
					children << n
				}
			}
		}
	}
	return TemplateNode{
		name: name.to_lower()
		attrs: attrs
		children: children
		self_close: self_closing
	}
}

fn (mut p TemplateParser) parse_text_node() TemplateNode {
	start := p.idx
	for !p.eof() && p.peek() != `<` {
		p.idx++
	}
	text := p.src[start..p.idx]
	return TemplateNode{
		is_text: true
		text: text
	}
}

fn (mut p TemplateParser) parse_identifier() string {
	start := p.idx
	for !p.eof() {
		ch := p.peek()
		if !(ch.is_letter() || ch.is_digit() || ch in [`_`, `-`, `:`]) {
			break
		}
		p.idx++
	}
	return p.src[start..p.idx]
}

fn (mut p TemplateParser) parse_attribute_value() string {
	if p.eof() {
		return ''
	}
	quote := p.peek()
	if quote == `"` || quote == `'` {
		p.idx++
		start := p.idx
		for !p.eof() && p.peek() != quote {
			p.idx++
		}
		value := p.src[start..p.idx]
		if !p.eof() {
			p.idx++
		}
		return value
	} else if quote == `{` {
		p.idx++
		start := p.idx
		for !p.eof() && p.peek() != `}` {
			p.idx++
		}
		value := p.src[start..p.idx]
		if !p.eof() {
			p.idx++
		}
		return '{' + value + '}'
	}
	start := p.idx
	for !p.eof() {
		ch := p.peek()
		if ch.is_space() || ch in [`>`, `/`] {
			break
		}
		p.idx++
	}
	return p.src[start..p.idx]
}

fn (mut p TemplateParser) skip_whitespace() {
	for !p.eof() && p.peek().is_space() {
		p.idx++
	}
}

fn (p TemplateParser) starts_with(prefix string) bool {
	remaining := p.src.len - p.idx
	if remaining < prefix.len {
		return false
	}
	return p.src[p.idx..p.idx + prefix.len] == prefix
}

fn (p TemplateParser) eof() bool {
	return p.idx >= p.src.len
}

fn (p TemplateParser) peek() u8 {
	return p.src[p.idx]
}

fn (mut p TemplateParser) expect(ch u8) {
	if p.eof() {
		return
	}
	if p.peek() == ch {
		p.idx++
	}
}

// Node building -------------------------------------------------------------

type TemplateFactory = fn (NodeSpec) VNode

fn container_border_box_factory(spec NodeSpec) VNode {
	return container_border_box(BorderBoxNodeSpec{
		NodeSpec: spec
	})
}

const template_component_factories = {
	'box':                  TemplateFactory(box)
	'box_layout':           TemplateFactory(box)
	'button':               TemplateFactory(button)
	'border_box':           TemplateFactory(border_box)
	'container_border_box': TemplateFactory(container_border_box_factory)
	'horizontal':           TemplateFactory(horizontal)
	'vertical':             TemplateFactory(vertical)
	'hline':                TemplateFactory(hline)
	'vline':                TemplateFactory(vline)
	'text':                 TemplateFactory(text)
}

const event_name_map = {
	'onclick':      'click'
	'onmousedown':  'down'
	'onmouseup':    'up'
	'onmousemove':  'move'
	'onmousewheel': 'wheel'
}

pub fn view_from_template(src string, ctx TemplateContext) !VNode {
	mut parser := new_template_parser(src)
	mut nodes := parser.parse_all()!
	mut built := []VNode{}
	for node in nodes {
		built << build_template_node(node, ctx)!
	}
	mut flattened := []VNode{}
	for node in built {
		if node.constructor == '__empty__' {
			flattened << node.children
			continue
		}
		flattened << node
	}
	if flattened.len != 1 {
		return error('template requires exactly one root node, found ${flattened.len}')
	}
	return flattened[0]
}

fn build_template_node(node TemplateNode, ctx TemplateContext) !VNode {
	if node.is_text {
		text_value := interpolate_text(node.text, ctx.props).trim_space()
		if text_value.len == 0 {
			return empty_vnode()
		}
		return text(NodeSpec{
			tag:    'text-node'
			props:  TermProps{text: text_value}
			style:  default_box_style()
			children: []VNode{}
		})
	}
	if node.name == 'slot' {
		if ctx.children.len == 0 {
			return empty_vnode()
		}
		return wrap_children(ctx.children.clone())
	}
	factory := template_component_factories[node.name] or {
		return error('unknown template tag `${node.name}`')
	}
	style_map := parse_style_map(interpolate_text(node.attrs['style'] or { '' }, ctx.props))
	mut props := parse_props_from_attributes(node, style_map, ctx)
	mut style_spec := build_style_spec(style_map)
	mut events := parse_events_from_attributes(node, ctx)
	mut children := []VNode{}
	for child in node.children {
		child_node := build_template_node(child, ctx)!
		if child_node.constructor == '__empty__' {
			children << child_node.children
			continue
		}
		children << child_node
	}
	return factory(NodeSpec{
		tag:      node.attrs['id'] or { node.attrs['tag'] or { node.name } }
		props:    props
		style:    style_spec
		events:   events
		children: children
	})
}

fn empty_vnode() VNode {
	return VNode{
		constructor: '__empty__'
		children: []VNode{}
	}
}

fn wrap_children(children []VNode) VNode {
	return VNode{
		constructor: '__empty__'
		children: children
	}
}

fn parse_events_from_attributes(node TemplateNode, ctx TemplateContext) []UiEventHandler {
	mut events := []UiEventHandler{}
	for attr, raw_value in node.attrs {
		if !attr.starts_with('on') {
			continue
		}
		mut pattern := ''
		if attr.starts_with('on:') {
			pattern = attr[3..]
		} else {
			pattern = event_name_map[attr] or {
				attr[2..]
			}
		}
		handler_name := normalized_handler_name(raw_value, ctx)
		if handler_name.len == 0 {
			continue
		}
		handler := ctx.handlers[handler_name] or {
			continue
		}
		events << on(pattern, handler)
	}
	return events
}

fn normalized_handler_name(value string, ctx TemplateContext) string {
	mut v := interpolate_text(value, ctx.props).trim_space()
	if v.len >= 2 && v[0] == `{` && v[v.len - 1] == `}` {
		v = v[1..v.len - 1].trim_space()
	}
	return v
}

fn parse_props_from_attributes(node TemplateNode, style_map map[string]string, ctx TemplateContext) TermProps {
	mut props := TermProps{}
	if v := resolve_numeric_attr(node, style_map, ctx, 'top') {
		props.top = v
	}
	if v := resolve_numeric_attr(node, style_map, ctx, 'left') {
		props.left = v
	}
	if v := resolve_numeric_attr(node, style_map, ctx, 'width') {
		props.width = v
	}
	if v := resolve_numeric_attr(node, style_map, ctx, 'height') {
		props.height = v
	}
	if text_value := resolve_string_attr(node, style_map, ctx, 'text') {
		props.text = text_value
	}
	return props
}

fn resolve_numeric_attr(node TemplateNode, style_map map[string]string, ctx TemplateContext, key string) ?int {
	if value := node.attrs[key] {
		if parsed := parse_int(interpolate_text(value, ctx.props)) {
			return parsed
		}
	}
	if value := style_map[key] {
		if parsed := parse_int(value) {
			return parsed
		}
	}
	return none
}

fn resolve_string_attr(node TemplateNode, style_map map[string]string, ctx TemplateContext, key string) ?string {
	if value := node.attrs[key] {
		return interpolate_text(value, ctx.props)
	}
	if value := style_map[key] {
		return value
	}
	return none
}

fn parse_style_map(raw string) map[string]string {
	mut res := map[string]string{}
	if raw.len == 0 {
		return res
	}
	mut normalized := raw.replace(',', ';')
	for part in normalized.split(';') {
		segment := part.trim_space()
		if segment.len == 0 {
			continue
		}
		idx := segment.index(':') or { continue }
		key := segment[..idx].trim_space().to_lower()
		value := segment[idx + 1..].trim_space()
		if key.len == 0 {
			continue
		}
		res[key] = value
	}
	return res
}

fn build_style_spec(style_map map[string]string) TermStyleSpec {
	base := default_box_style()
	mut background := base.default.background
	mut foreground := base.default.foreground
	mut border := base.default.border
	mut line := base.default.line
	if v := style_map['bg'] {
		if c := parse_color(v) {
			background = c
		}
	} else if v := style_map['background'] {
		if c := parse_color(v) {
			background = c
		}
	}
	if v := style_map['fg'] {
		if c := parse_color(v) {
			foreground = c
		}
	} else if v := style_map['foreground'] {
		if c := parse_color(v) {
			foreground = c
		}
	}
	if v := style_map['border'] {
		border = v
	}
	if v := style_map['line'] {
		line = v
	}
	return make_stylesheet(
		background: background
		foreground: foreground
		border: border
		line: line
	)
}

fn parse_color(value string) ?TermColor {
	mut v := value.trim_space()
	if v.len == 0 {
		return none
	}
	if v[0] == `#` {
		v = v[1..]
	}
	if v.len != 6 {
		return none
	}
	r := strconv.parse_int(v[..2], 16, 0) or { return none }
	g := strconv.parse_int(v[2..4], 16, 0) or { return none }
	b := strconv.parse_int(v[4..6], 16, 0) or { return none }
	return TermColor{u8(r), u8(g), u8(b)}
}

fn parse_int(value string) ?int {
	trimmed := value.trim_space()
	if trimmed.len == 0 {
		return none
	}
	return strconv.atoi(trimmed) or { return none }
}

fn interpolate_text(value string, props map[string]string) string {
	if value.len == 0 || props.len == 0 {
		return value
	}
	mut builder := strings.new_builder(value.len)
	mut i := 0
	for i < value.len {
		if i + 1 < value.len && value[i] == `{` && value[i + 1] == `{` {
			j := index_after(value, '}}', i + 2)
			if j == -1 {
				builder.write_byte(value[i])
				i++
				continue
			}
			key := value[i + 2..j].trim_space()
			builder.write_string(props[key] or { '' })
			i = j + 2
			continue
		}
		builder.write_byte(value[i])
		i++
	}
	return builder.str()
}

fn index_after(s string, substr string, start int) int {
	if substr.len == 0 || start >= s.len {
		return -1
	}
	mut i := start
	for i + substr.len <= s.len {
		if s[i..i + substr.len] == substr {
			return i
		}
		i++
	}
	return -1
}
