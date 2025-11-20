module main

import strings

#flag -I @VMODROOT/c-components
#flag -D STB_IMAGE_IMPLEMENTATION
#flag -D STBI_NO_SIMD
#flag linux -lm
#include "stb_image.h"

fn C.stbi_load(filename &char, x &int, y &int, comp &int, req_comp int) &u8
fn C.stbi_image_free(ret voidptr)

struct ImageData {
	width    int
	height   int
	channels int
	data     &u8
}

fn (img &ImageData) free() {
	unsafe {
		if !isnil(img.data) {
			C.stbi_image_free(voidptr(img.data))
		}
	}
}

fn load_image(filename string, req_channels int) !ImageData {
	if filename.len == 0 {
		return error('empty filename')
	}
	mut w := 0
	mut h := 0
	mut comp := 0
	unsafe {
		data := C.stbi_load(filename.str, &w, &h, &comp, req_channels)
		if isnil(data) {
			return error('failed to load image ${filename}')
		}
		actual_channels := if req_channels != 0 { req_channels } else { comp }
		return ImageData{
			width: w
			height: h
			channels: actual_channels
			data: data
		}
	}
}

fn image_to_ascii(data ImageData, width int, threshold int, color bool) string {
	if width <= 0 || data.width == 0 || data.height == 0 {
		return ''
	}
	mut target_width := width
	if target_width > data.width {
		target_width = data.width
	}
	mut aspect := f64(data.height) / f64(data.width)
	if aspect <= 0 {
		aspect = 1
	}
	mut target_height := int(aspect * f64(target_width))
	if target_height < 1 {
		target_height = 1
	}
	mut builder := strings.new_builder((target_width + 8) * (target_height + 2))
	mut idx := 0
	for ty in 0 .. target_height {
		mut src_y := int(f64(ty) / f64(target_height) * f64(data.height))
		if src_y >= data.height {
			src_y = data.height - 1
		}
		for tx in 0 .. target_width {
			mut src_x := int(f64(tx) / f64(target_width) * f64(data.width))
			if src_x >= data.width {
				src_x = data.width - 1
			}
			mut pixel_index := (src_y * data.width + src_x) * data.channels
			if pixel_index >= data.width * data.height * data.channels {
				pixel_index = (data.width * data.height * data.channels) - data.channels
			}
			unsafe {
				r := data.data[pixel_index]
				g := if data.channels >= 2 { data.data[pixel_index + 1] } else { r }
				b := if data.channels >= 3 { data.data[pixel_index + 2] } else { r }
				brightness := (int(r) + int(g) + int(b)) / 3
				if color {
					if brightness < threshold {
						builder.write_string('  ')
					} else {
						builder.write_string('\x1b[48;2;${r};${g};${b}m  \x1b[0m')
					}
				} else {
					mut char_set := ' .:-=+*#%@'
					mut index := int(f64(brightness) / 255.0 * f64(char_set.len - 1))
					if brightness < threshold {
						index = 0
					}
					builder.write_u8(char_set[index])
				}
			}
			idx++
		}
		builder.write_u8(`\n`)
	}
	return builder.str()
}

pub fn image_to_color_str(image_filename string, threshold int, width int) string {
    img := load_image(image_filename, 3) or {
        return ''
    }
	defer {
		img.free()
	}
	return image_to_ascii(img, width, threshold, true)
}

pub fn image_to_grayscale_str(image_filename string, threshold int, width int) string {
	img := load_image(image_filename, 3) or {
		return ''
	}
	defer {
		img.free()
	}
	return image_to_ascii(img, width, threshold, false)
}
