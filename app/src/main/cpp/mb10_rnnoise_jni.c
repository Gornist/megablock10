#include <jni.h>
#include <stddef.h>
#include "mb10_rnnoise.h"
#include "rnnoise.h"

/* com.megablok10.app.call.RnNoiseNative: состояние RNNoise на один поток микрофона; кадры — прямой ByteBuffer с float, обработка на месте (без копий и без аллокаций). */

JNIEXPORT jlong JNICALL Java_com_megablok10_app_call_RnNoiseNative_create(JNIEnv *env, jclass cls) {
    (void)env; (void)cls;
    return (jlong)(intptr_t)rnnoise_create(NULL);
}

JNIEXPORT void JNICALL Java_com_megablok10_app_call_RnNoiseNative_destroy(JNIEnv *env, jclass cls, jlong handle) {
    (void)env; (void)cls;
    if (handle) rnnoise_destroy((DenoiseState *)(intptr_t)handle);
}

/* Возвращает вероятность речи (0..1) либо -1, если буфер не годится (не прямой, меньше кадра). Ровно один кадр MB10_FRAME отсчётов. */
JNIEXPORT jfloat JNICALL Java_com_megablok10_app_call_RnNoiseNative_process(JNIEnv *env, jclass cls, jlong handle, jobject buffer, jint frames) {
    (void)cls;
    if (!handle || frames != MB10_FRAME) return -1.0f;
    float *samples = (float *)(*env)->GetDirectBufferAddress(env, buffer);
    if (!samples || (*env)->GetDirectBufferCapacity(env, buffer) < (jlong)(frames * (jint)sizeof(float))) return -1.0f;
    return rnnoise_process_frame((DenoiseState *)(intptr_t)handle, samples, samples);
}

JNIEXPORT jfloat JNICALL Java_com_megablok10_app_call_RnNoiseNative_selfTestDb(JNIEnv *env, jclass cls) {
    (void)env; (void)cls;
    return mb10_rnnoise_selftest_db(NULL);
}
