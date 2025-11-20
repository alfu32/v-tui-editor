module main

fn test_image_to_grayscale_str() {
	result := image_to_grayscale_str('c-components/flower.jpg', 30, 20)
	assert result.len > 0
	lines := result.trim_space_right().split('\n')
	assert lines.len >= 1
}

fn test_image_to_color_str() {
	result := image_to_color_str('c-components/flower.jpg', 10, 20)
	assert result.len > 0
	assert result.contains('\x1b[48;2;')
}
