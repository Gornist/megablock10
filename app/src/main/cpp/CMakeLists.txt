# Нативная часть приложения: шумоподавление микрофона звонка (RNNoise, BSD-3 — rnnoise/COPYING) и JNI-обёртка.
# Собирается Gradle (app/build.gradle.kts, externalNativeBuild); для проверки на хосте без Android — check/check.sh.
cmake_minimum_required(VERSION 3.22.1)
project(mb10rnnoise C)

set(RNNOISE_SRC
    rnnoise/src/denoise.c
    rnnoise/src/rnn.c
    rnnoise/src/rnn_data.c
    rnnoise/src/pitch.c
    rnnoise/src/kiss_fft.c
    rnnoise/src/celt_lpc.c)

add_library(mb10rnnoise SHARED ${RNNOISE_SRC} mb10_rnnoise.c mb10_rnnoise_jni.c)
target_include_directories(mb10rnnoise PRIVATE rnnoise/include rnnoise/src)
target_compile_options(mb10rnnoise PRIVATE -O3 -fvisibility=hidden -DNDEBUG)
# Android 15+: страницы по 16 КБ (NDK r28 делает это сам, для прежних — явно).
target_link_options(mb10rnnoise PRIVATE -Wl,-z,max-page-size=16384)
find_library(LOG_LIB log)
target_link_libraries(mb10rnnoise ${LOG_LIB} m)
