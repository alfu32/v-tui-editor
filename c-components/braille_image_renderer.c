#define STB_IMAGE_IMPLEMENTATION
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <wchar.h>
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
    setlocale(LC_ALL, "");

    int use_color = 0;
    int threshold = 128;

    if (argc < 2) {
        fprintf(stderr, "usage: %s image.(png|jpg) [threshold|color]\n", argv[0]);
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
    int term_w = get_terminal_width();

    if (argc >= 4) {
        term_w = atoi(argv[3]);
    }

    if(use_color){
        printf("using parameters:\nfilename:%s,\ncolor,\nterm width:%d\n",argv[1],term_w);
    }else{
        printf("using parameters:\nfilename:%s,\nbw,\n,threshold:%d,\nterm width:%d\n",argv[1],threshold,term_w);
    }
    int w, h, c;
    uint8_t *img = stbi_load(argv[1], &w, &h, &c, 3);
    if (!img) {
        fprintf(stderr, "cannot load image\n");
        return 1;
    }

    int output_w_cells = term_w;
    int input_w_target = output_w_cells * 2;

    float scale = (float)input_w_target / (float)w;
    int out_w_px = input_w_target;
    int out_h_px = (int)(h * scale);

    for (int y = 0; y < out_h_px; y += 4) {
        for (int x = 0; x < out_w_px; x += 2) {

            int dots = 0;

            int sum_r = 0, sum_g = 0, sum_b = 0;
            int samples = 0;

            for (int dy = 0; dy < 4; dy++) {
                for (int dx = 0; dx < 2; dx++) {

                    int src_x = (int)((float)(x + dx) / scale);
                    int src_y = (int)((float)(y + dy) / scale);

                    if (src_x >= w || src_y >= h)
                        continue;

                    uint8_t *p = img + (src_y * w + src_x) * 3;
                    int r = p[0];
                    int g = p[1];
                    int b = p[2];
                    int gray = (r + g + b) / 3;

                    int bit_index = (dx == 0 ? 0 : 3) + dy;
                    if (gray < threshold)
                        dots |= (1 << bit_index);

                    if (use_color) {
                        sum_r += r;
                        sum_g += g;
                        sum_b += b;
                        samples++;
                    }
                }
            }

            wchar_t ch = (wchar_t)(0x2800 + dots);

            if (use_color && samples > 0) {
                int avg_r = sum_r / samples;
                int avg_g = sum_g / samples;
                int avg_b = sum_b / samples;

                printf("\x1b[38;2;%d;%d;%dm%lc\x1b[0m",
                        avg_r, avg_g, avg_b, ch);
            } else {
                printf("%lc", ch);
            }
        }
        printf("\n");
    }

    stbi_image_free(img);
    return 0;
}
