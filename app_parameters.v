module main

import reactive
import editor

pub const top_bar_height = 3
pub const status_bar_height = 1
pub const divider_width = 1
pub const min_left_width = 12
pub const min_right_width = 20
pub const editor_gutter_chars = editor.default_gutter_width + 2
pub const whitespace_runes = [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
pub const editor_bg_color = reactive.TermColor{16, 20, 28}
pub const editor_fg_color = reactive.TermColor{210, 210, 210}
pub const editor_cursor_bg = reactive.TermColor{210, 210, 210}
pub const editor_cursor_fg = reactive.TermColor{20, 24, 32}
pub const editor_selection_bg = reactive.TermColor{60, 80, 120}
pub const editor_selection_fg = reactive.TermColor{255, 255, 255}
pub const scrollbar_width = 1
