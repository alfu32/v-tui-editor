import reactive

fn templated_panel(message string, children []reactive.VNode) reactive.VNode {
	close_handler := fn [message] (mut e reactive.UiEvent) {
		e.renderer.ctx.log('templated close button clicked (${message})', @FN + ' ' + @FILE_LINE)
	}
	ctx := reactive.TemplateContext{
		props: {
			'message': message
		}
		handlers: {
			'close_handler': close_handler
		}
		children: children
	}
	return reactive.view_from_template('
<box_layout style="top:17;left:2;width:60;height:12;bg:#202840;fg:#d2d2d2;border:box_light_rounded">
	<button onclick={close_handler} style="top:1;left:2;width:24;height:3;bg:#a05c20;fg:#202020">
		Close templated panel
	</button>
	<text style="top:5;left:2;width:54;height:1">{{message}}</text>
	<slot/>
</box_layout>
'.trim_indent(), ctx) or {
		reactive.text(
			tag: 'template-error'
			props: reactive.TermProps{
				text: 'template error: ' + err.msg()
			}
		)
	}
}

fn root_view() reactive.VNode {
	templated_children := [
		reactive.text(
			tag: 'slot-message'
			props: reactive.TermProps{
				top: 7
				left: 2
				text: 'Slot content injected via <slot/>'
			}
		)
	]
	return reactive.box(
		tag: 	"main"
		props:    reactive.TermProps{
			top:    0
			left:   0
			width:  0 // fill viewport
			height: 0
		}
		style:reactive.make_stylesheet(
			background: reactive.TermColor{32, 32, 32}
			foreground: reactive.TermColor{192, 192, 192}
			border: 'box_light_straight'
			line:'line_simple_simple'
		)
		events:   [
			reactive.on('ctrl-c', fn (mut e reactive.UiEvent) {
				e.propagate = true
				e.renderer.ctx.log('Ctrl-C exit called',@FN+" "+@FILE_LINE)
				e.renderer.ctx.dump_messages_to_file('ctrl-c-exit.log')
				e.renderer.app.will_exit(0)
			}),
		]
		children: [
			reactive.button(
				tag: 	"close-button"
				props:    reactive.TermProps{
					top:    1
					left:   1
					width:  20
					height: 3
				}
				style:reactive.make_stylesheet(
					background: reactive.TermColor{160, 92, 32}
					foreground: reactive.TermColor{32,32,32}
					border: 'empty'
					line:'empty'
				)
				events:   [
					reactive.on('click', fn (mut e reactive.UiEvent) {
						e.propagate = true
						e.renderer.ctx.log('exit button clicked',@FN+" "+@FILE_LINE)
						e.renderer.ctx.dump_messages_to_file('click-exit.log')
						e.renderer.app.will_exit(0)
					}),
				]
				children: [reactive.text(
					tag: 	"button-text"
					props: reactive.TermProps{
						top:  1
						left: 3
						text: 'Click To Close'
					}
				),
				]
			)
			reactive.container_border_box(
				tag: 	"big-box"
				props:    reactive.TermProps{
					top:    6
					left:   12
					width:  40
					height: 9
				}
				style:reactive.make_stylesheet(
					background: reactive.TermColor{64, 32, 32}
					foreground: reactive.TermColor{192, 192, 192}
					border: 'box_light_straight'
				)
				events:   [
					reactive.on('ctrl-c', fn (mut e reactive.UiEvent) {
						e.propagate = true
						e.renderer.ctx.log('Ctrl-C exit called on button',@FN+" "+@FILE_LINE)
						e.renderer.ctx.dump_messages_to_file('ctrl-c-exit.log')
						e.renderer.app.will_exit(0)
					}),
					reactive.on('click', fn (mut e reactive.UiEvent) {
						e.propagate = true
						e.renderer.ctx.log('exit button clicked',@FN+" "+@FILE_LINE)
						e.renderer.ctx.dump_messages_to_file('click-exit.log')
						e.renderer.app.will_exit(0)
					}),
				]
				children: [
					reactive.hline(
						tag: 	"h-line-button"
						props: reactive.TermProps{
							top:   5
							left:  0
						}
						style: reactive.default_box_style()
					),
					reactive.vline(
						tag: 	"v-line-button"
						props: reactive.TermProps{
							top:    0
							left:   12
						}
						style: reactive.default_box_style()
					),
					reactive.text(
						tag: 	"button-text"
						props: reactive.TermProps{
							top:  3
							left: 3
							text: 'Hello reactive term UI'
						}
					),
				]
			),
			templated_panel('Templates render runtime markup', templated_children),
		]
	)
}

fn main() {
	mut app := reactive.reactive_app(root_view)
	app.run()!
}
