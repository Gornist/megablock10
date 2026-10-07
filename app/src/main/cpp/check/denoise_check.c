/* Проверка RNNoise на хосте (без Android): шум стационарного вентилятора давится больше чем на 10 дБ, тишина остаётся тишиной. Запуск: check/check.sh */
#include <stdio.h>
#include "../mb10_rnnoise.h"

int main(void) {
    float silence_peak = 0.0f;
    float db = mb10_rnnoise_selftest_db(&silence_peak);
    printf("ослабление стационарного шума: %.1f дБ, пик на тишине: %.2f\n", db, silence_peak);
    int ok = 1;
    if (db < 10.0f) { printf("FAIL: шум подавлен меньше чем на 10 дБ\n"); ok = 0; }
    if (silence_peak > 50.0f) { printf("FAIL: на тишине выход не тихий\n"); ok = 0; }
    printf(ok ? "OK\n" : "FAIL\n");
    return ok ? 0 : 1;
}
