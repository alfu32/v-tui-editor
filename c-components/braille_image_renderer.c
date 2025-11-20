#define STB_IMAGE_IMPLEMENTATION
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <locale.h>
#include "stb_image.h"

static inline int braille_dot(int bit) {
    return 1 << bit;
}

static uint32_t get_terminal_width() {
    FILE *p = popen("tput cols", "r");
    if (!p) return 80;
    char buf[32];
    fgets(buf, sizeof(buf), p);
    pclose(p);
    return atoi(buf);
}

int main(int argc, char **argv) {
    int use_color = 0;
    int threshold = 128;
    setlocale(LC_ALL, "");
    if (argc < 2) {
        fprintf(stderr, "usage: %s image.(png|jpg)\n", argv[0]);
        return 1;
    }
    if (argc >= 3) {
        if (strcmp(argv[2], "color") == 0) {
            use_color = 1;
        } else {
            threshold = atoi(argv[2]);
            if (threshold < 0) threshold = 0;
            if (threshold > 255) threshold = 255;
        }
    }

    int w, h, c;
    uint8_t *img = stbi_load(argv[1], &w, &h, &c, 3);
    if (!img) {
        fprintf(stderr, "cannot load image\n");
        return 1;
    }

    int term_w = get_terminal_width();
    int output_w_cells = term_w;
    int input_w_target = output_w_cells * 2;

    float scale = (float)input_w_target / w;
    int out_w_px = input_w_target;
    int out_h_px = (int)(h * scale);

    for (int y = 0; y < out_h_px; y += 4) {
        for (int x = 0; x < out_w_px; x += 2) {

            int dots = 0;

            for (int dy = 0; dy < 4; dy++) {
                for (int dx = 0; dx < 2; dx++) {

                    int src_x = (int)(x + dx) / scale;
                    int src_y = (int)(y + dy) / scale;

                    if (src_x >= w || src_y >= h)
                        continue;

                    uint8_t *p = img + (src_y * w + src_x) * 3;
                    int gray = (p[0] + p[1] + p[2]) / 3;

                    int bit_index =
                        (dx == 0 ? 0 : 3) + dy;

                        int r = p[0];
                        int g = p[1];
                        int b = p[2];

                        // grayscale threshold still used for deciding ON/OFF of dots
                        int gray = (r + g + b) / 3;
                        if (gray < threshold)
                        bits |= (1 << dot_index);

                        // accumulate color for averaging
                        sum_r += r;
                        sum_g += g;
                        sum_b += b;
                        samples++;
                }
            }

            uint32_t cp = 0x2800 + dots;
            printf("%lc", cp);
        }
        printf("\n");
    }

    stbi_image_free(img);
    return 0;
}
