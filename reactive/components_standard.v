module reactive

// standard components shared across apps

pub struct ButtonSpec {
pub:
	tag     string
	left    int
	top     int
	label   string
	handler UiEventHandler
}

fn button_style() TermStyleSpec {
	return make_stylesheet(
		background: TermColor{70, 90, 130}
		foreground: TermColor{255, 255, 255}
		border:     'box_light_rounded'
		line:       'line_simple_simple'
	)
}

fn button_text_style() TermStyleSpec {
	return make_stylesheet(
		background: TermColor{70, 90, 130}
		foreground: TermColor{255, 255, 255}
		border:     'empty'
		line:       'empty'
	)
}

pub fn make_button(spec ButtonSpec) VNode {
	mut width := spec.label.len + 4
	if width < 8 {
		width = 8
	}
	mut text_left := (width - spec.label.len) / 2
	if text_left < 1 {
		text_left = 1
	}
	return rect(NodeSpec{
		tag:      spec.tag
		props:    TermProps{
			left:   spec.left
			top:    spec.top
			width:  width
			height: 3
		}
		style:    button_style()
		events:   [spec.handler]
		children: [
			text(NodeSpec{
				props: TermProps{
					top:  1
					left: text_left
					text: spec.label
				}
				style: button_text_style()
			}),
		]
	})
}

pub struct ScrollbarState {
pub mut:
	dragging    bool
	drag_offset int
}

pub type ScrollMetricFn = fn (voidptr) int

pub type ScrollSetterFn = fn (voidptr, int)

pub struct ScrollbarBindings {
pub:
	context    voidptr
	viewport   ScrollMetricFn
	total      ScrollMetricFn
	offset     ScrollMetricFn
	set_offset ScrollSetterFn
}

fn scrollbar_track_style() TermStyleSpec {
	return make_stylesheet(
		background: TermColor{26, 32, 44}
		foreground: TermColor{110, 120, 140}
		border:     'empty'
		line:       'empty'
	)
}

fn scrollbar_thumb_style() TermStyleSpec {
	return make_stylesheet(
		background: TermColor{52, 78, 120}
		foreground: TermColor{210, 210, 210}
		border:     'empty'
		line:       'empty'
	)
}

fn clampi(value int, min_val int, max_val int) int {
	mut v := value
	if v < min_val {
		v = min_val
	}
	if v > max_val {
		v = max_val
	}
	return v
}

fn thumb_size(track int, viewport int, total int) int {
	if track <= 0 {
		return 0
	}
	if total <= 0 || viewport <= 0 || total <= viewport {
		return track
	}
	mut size := (track * track) / total
	if size < 3 {
		size = 3
	}
	if size > track {
		size = track
	}
	return size
}

fn thumb_local(track int, viewport int, total int, offset int, thumb int) int {
	if track <= thumb || total <= viewport {
		return 0
	}
	max_offset := total - viewport
	if max_offset <= 0 {
		return 0
	}
	track_range := track - thumb
	mut pos := int(f64(offset) / f64(max_offset) * f64(track_range))
	return clampi(pos, 0, track_range)
}

fn offset_from_thumb(track int, viewport int, total int, thumb int, local int) int {
	if total <= viewport || track <= thumb {
		return 0
	}
	max_offset := total - viewport
	track_range := track - thumb
	if track_range <= 0 {
		return 0
	}
	mut ratio := f64(local) / f64(track_range)
	if ratio < 0 {
		ratio = 0
	}
	if ratio > 1 {
		ratio = 1
	}
	return int(ratio * f64(max_offset) + 0.5)
}

pub fn vertical_scrollbar(tag string, rect TermRect, bindings ScrollbarBindings, mut state ScrollbarState, track_width int) ?VNode {
	if rect.height <= 0 || track_width <= 0 {
		return none
	}
	metrics := bindings_metrics(bindings)
	thumb := thumb_size(rect.height, metrics.viewport, metrics.total)
	if thumb <= 0 {
		return none
	}
	thumb_pos := thumb_local(rect.height, metrics.viewport, metrics.total, metrics.offset,
		thumb)
	mut children := []VNode{}
	for i in 0 .. rect.height - 1 {
		children << text(NodeSpec{
			props: TermProps{
				top:  i
				text: '║'
			}
			style: scrollbar_track_style()
		})
	}
	for i in 0 .. thumb - 1 {
		children << text(NodeSpec{
			props: TermProps{
				top:  thumb_pos + i
				text: '█'
			}
			style: scrollbar_thumb_style()
		})
	}
	return relative(NodeSpec{
		tag:      tag
		props:    TermProps{
			left:   rect.x
			top:    rect.y
			width:  track_width
			height: rect.height
		}
		style:    scrollbar_track_style()
		children: children
		events:   [
			fn [rect, bindings, mut state] (mut e UiEvent) {
				metrics := bindings_metrics(bindings)
				thumb := thumb_size(rect.height, metrics.viewport, metrics.total)
				if thumb <= 0 {
					return
				}
				thumb_pos := thumb_local(rect.height, metrics.viewport, metrics.total,
					metrics.offset, thumb)
				local_y := clampi(e.mouse.y - rect.y, 0, rect.height - 1)
				track_range := if rect.height > thumb { rect.height - thumb } else { 0 }
				if e.kind == .mouse_down {
					if local_y >= thumb_pos && local_y < thumb_pos + thumb {
						state.dragging = true
						state.drag_offset = local_y - thumb_pos
					} else {
						state.dragging = true
						state.drag_offset = thumb / 2
						mut new_thumb := clampi(local_y - state.drag_offset, 0, track_range)
						new_offset := offset_from_thumb(rect.height, metrics.viewport,
							metrics.total, thumb, new_thumb)
						bindings.set_offset(bindings.context, new_offset)
					}
				} else if e.kind == .mouse_move && state.dragging {
					mut new_thumb := clampi(local_y - state.drag_offset, 0, track_range)
					new_offset := offset_from_thumb(rect.height, metrics.viewport, metrics.total,
						thumb, new_thumb)
					bindings.set_offset(bindings.context, new_offset)
				} else if e.kind == .mouse_up {
					state.dragging = false
				}
			},
		]
	})
}

fn bindings_metrics(bindings ScrollbarBindings) ScrollbarMetrics {
	return ScrollbarMetrics{
		viewport: bindings.viewport(bindings.context)
		total:    bindings.total(bindings.context)
		offset:   bindings.offset(bindings.context)
	}
}

pub struct ScrollbarMetrics {
pub:
	viewport int
	total    int
	offset   int
}

pub fn horizontal_scrollbar(tag string, rect TermRect, bindings ScrollbarBindings, mut state ScrollbarState) ?VNode {
	if rect.width <= 0 || rect.height <= 0 {
		return none
	}
	metrics := bindings_metrics(bindings)
	thumb := thumb_size(rect.width, metrics.viewport, metrics.total)
	if thumb <= 0 {
		return none
	}
	thumb_pos := thumb_local(rect.width, metrics.viewport, metrics.total, metrics.offset,
		thumb)
	mut children := []VNode{}
	for i in 0 .. rect.width - 1 {
		children << text(NodeSpec{
			props: TermProps{
				left: i
				text: '═'
			}
			style: scrollbar_track_style()
		})
	}
	for i in 0 .. thumb - 1 {
		children << text(NodeSpec{
			props: TermProps{
				left: thumb_pos + i
				text: '█'
			}
			style: scrollbar_thumb_style()
		})
	}
	return relative(NodeSpec{
		tag:      tag
		props:    TermProps{
			left:   rect.x
			top:    rect.y
			width:  rect.width
			height: rect.height
		}
		style:    scrollbar_track_style()
		children: children
		events:   [
			fn [rect, bindings, mut state] (mut e UiEvent) {
				metrics := bindings_metrics(bindings)
				thumb := thumb_size(rect.width, metrics.viewport, metrics.total)
				if thumb <= 0 {
					return
				}
				thumb_pos := thumb_local(rect.width, metrics.viewport, metrics.total,
					metrics.offset, thumb)
				local_x := clampi(e.mouse.x - rect.x, 0, rect.width - 1)
				track_range := if rect.width > thumb { rect.width - thumb } else { 0 }
				if e.kind == .mouse_down {
					if local_x >= thumb_pos && local_x < thumb_pos + thumb {
						state.dragging = true
						state.drag_offset = local_x - thumb_pos
					} else {
						state.dragging = true
						state.drag_offset = thumb / 2
						mut new_thumb := clampi(local_x - state.drag_offset, 0, track_range)
						new_offset := offset_from_thumb(rect.width, metrics.viewport,
							metrics.total, thumb, new_thumb)
						bindings.set_offset(bindings.context, new_offset)
					}
				} else if e.kind == .mouse_move && state.dragging {
					mut new_thumb := clampi(local_x - state.drag_offset, 0, track_range)
					new_offset := offset_from_thumb(rect.width, metrics.viewport, metrics.total,
						thumb, new_thumb)
					bindings.set_offset(bindings.context, new_offset)
				} else if e.kind == .mouse_up {
					state.dragging = false
				}
			},
		]
	})
}
