# Шумоподавление микрофона звонка (RNNoise)

Решение владельца 07.10.2026: «кулер, шумящий рядом с телефоном, слышу так же чётко, как голос» — встроенный NS телефона и штатный NS WebRTC на слух не различались, поэтому нейросетевой
шумодав RNNoise включён в звонках по умолчанию (без A/B и отладочной сборки).

## Как устроено

- `src/main/cpp/rnnoise/` — исходники RNNoise (Mozilla/Xiph, BSD-3, `COPYING`; копия AOSP `external/rnnoise`, версия с зашитой моделью `rnn_data.c`). Текст лицензии лежит в приложении:
  `assets/licenses/rnnoise.txt`.
- `src/main/cpp/mb10_rnnoise*.c`, `CMakeLists.txt` — JNI-обёртка (`call.RnNoiseNative`) и самопроверка; собирается Gradle (`externalNativeBuild`, CMake 3.22.1, NDK 28.1; ABI arm64-v8a,
  armeabi-v7a, x86_64, x86; +≈0,12–0,15 МБ на ABI).
- Хук: `ExternalAudioProcessingFactory.setCapturePostProcessing` (webrtc-sdk) отдаёт каждые 10 мс моно-буфер (канал 0) float в шкале int16 — ровно кадр RNNoise при 48 кГц.
  `call.RnNoiseProcessor` обрабатывает кадр на месте. Тракт не 48 кГц или сбой init/кадров — кадр идёт как есть (штатный NS), в журнале `call.rnnoise_bypass` / `call.rnnoise state=…`.
  Библиотека не загрузилась — внешняя обработка не ставится вообще, звонок как раньше (`call.audio_denoise rnnoiseLib=false`).
- Выключатель для сравнения на слух (debug-сборка): `DEBUG_SET --es callaudio "rnnoise=0"` / `"rnnoise=1"` — на лету, без перезапуска звонка (bypass-флаг).

## Проверки

- Хост, без Android: `app/src/main/cpp/check/check.sh` — стационарный шум (белый + НЧ + гул) ослабляется ≥ 10 дБ (получается ≈18), тишина остаётся тишиной. Нужен только `cc`.
- Эмулятор: сценарий e2e `rnnoise.sh` — `DEBUG_SET --es rnnoisetest 1` гоняет ту же самопроверку через JNI (библиотека загрузилась, ≥ 10 дБ), переключатель не роняет приложение.
- Юнит: `RnNoiseProcessorTest` (подмена движка: только 48 кГц и целые кадры, откат при сбоях).
- Телефоны: приёмка владельцем «кулер рядом» до/после (звонок T1↔T2).

## Ограничения

Шумодав работает на стороне отправителя (микрофон), моно. Голосовые сообщения (`MediaRecorder`) он не затрагивает — отдельная задача: AudioRecord + RNNoise + AAC-кодек.
