#include "mb10_rnnoise.h"

#include <math.h>
#include <stddef.h>
#include "rnnoise.h"

float mb10_rnnoise_selftest_db(float *out_silence_peak) {
    DenoiseState *st = rnnoise_create(NULL);
    if (!st) return -1000.0f;
    unsigned seed = 12345u;
    float hum_phase = 0.0f, lp = 0.0f;
    double in_energy = 0.0, out_energy = 0.0;
    float buf[MB10_FRAME];
    for (int frame = 0; frame < 300; frame++) {
        for (int i = 0; i < MB10_FRAME; i++) {
            seed = seed * 1664525u + 1013904223u;
            float white = (((seed >> 8) & 0xFFFF) / 32768.0f - 1.0f) * 2500.0f;
            lp = 0.97f * lp + 0.03f * white * 6.0f; /* низкочастотный шум вентилятора */
            hum_phase += 6.2831853f * 120.0f / 48000.0f;
            buf[i] = white + lp + 1500.0f * sinf(hum_phase);
        }
        double e_in = 0.0;
        for (int i = 0; i < MB10_FRAME; i++) e_in += (double)buf[i] * buf[i];
        rnnoise_process_frame(st, buf, buf);
        if (frame >= 200) {
            double e_out = 0.0;
            for (int i = 0; i < MB10_FRAME; i++) e_out += (double)buf[i] * buf[i];
            in_energy += e_in;
            out_energy += e_out;
        }
    }
    float peak = 0.0f;
    for (int frame = 0; frame < 50; frame++) {
        for (int i = 0; i < MB10_FRAME; i++) buf[i] = 0.0f;
        rnnoise_process_frame(st, buf, buf);
        /* Первые кадры после шума — хвост окна и памяти сети; «тишиной» считаем выход после 20 кадров (200 мс). */
        if (frame >= 20) for (int i = 0; i < MB10_FRAME; i++) if (fabsf(buf[i]) > peak) peak = fabsf(buf[i]);
    }
    if (out_silence_peak) *out_silence_peak = peak;
    rnnoise_destroy(st);
    if (out_energy <= 0.0) out_energy = 1e-9;
    return (float)(10.0 * log10(in_energy / out_energy));
}
