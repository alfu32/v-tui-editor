import reactive

fn root_view() reactive.VNode {
	return reactive.box(reactive.NodeSpec{
		props:    reactive.TermProps{
			top:    0
			left:   0
			width:  0 // fill viewport
			height: 0
		}
		events:   [
			reactive.on('ctrl-c', fn (mut e reactive.UiEvent) {
				e.propagate = true
				println('Ctrl-C exit called')
				exit(0)
			}),
		]
		children: [
			reactive.border_box(reactive.NodeSpec{
				props:    reactive.TermProps{
					top:    2
					left:   4
					width:  40
					height: 7
				}
				events:   [
					reactive.on('click', fn (mut e reactive.UiEvent) {
						e.propagate = true
						println('Ctrl-C exit called')
						exit(0)
					}),
				]
				children: [
					reactive.hline(reactive.NodeSpec{
						props: reactive.TermProps{
							top:   0
							left:  0
							width: 40
						}
					}),
					reactive.vline(reactive.NodeSpec{
						props: reactive.TermProps{
							top:    0
							left:   0
							height: 7
						}
					}),
					reactive.text(reactive.NodeSpec{
						props: reactive.TermProps{
							top:  3
							left: 3
							text: 'Hello reactive term UI'
						}
					}),
				]
			}),
		]
	})
}

fn main() {
	mut app := reactive.reactive_app(root_view)
	app.run()!
}
