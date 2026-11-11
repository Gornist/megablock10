# Карточка E: голос — протокол в RemotePhoneLink и кодек кадров

**Цель:** `RemotePhoneLink` умеет JSON-кадры `voice`/`voice_ready` и бинарные кадры PCM (микрофон очков → телефон, звук собеседника → очки); это нижний слой, микрофона и динамика здесь НЕТ.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-voice-link`, ветка `agent/phone-voice-link` (от `agent/phone-voice-contract`). Копия на devbox — `~/wt-phone-voice-link`.

## Зона записи (только это)
`netrun/client/remote_phone_link.gd`, `netrun/shared/phone_voice_codec.gd` (новый, `class_name PhoneVoiceCodec`, + `.gd.uid` если создаётся), `netrun/tests/phone_voice_codec_test.gd` (новый), `netrun/tests/remote_phone_link_test.gd`.
НЕ трогать: `proto_client.gd`, `phone_sounds.gd`, деку, `phone_frames.json` (он уже готов), `docs/*`, export_presets/project.godot.

## Контракт (читай раздел «Голос» в `docs/netrun-phone-link.md`, подраздел после таблицы срезов; образцы — `netrun/tests/fixtures/phone_frames.json`: кадры `voice_*` и раздел `binary`)
- Бинарный кадр: `[1 байт тип][4 байта seq uint32 LE][PCM int16 LE моно]`. Тип 1 — микрофон очков → телефон; тип 2 — звук собеседника телефон → очки. Полезная часть чётной длины, ≤ 4096 байт. Частота — из `voice.rate` (по умолчанию 44100).
- JSON: телефон → очки `{"t":"voice","on":true,"rate":44100}` / `{"t":"voice","on":false}`; очки → телефон `{"t":"voice_ready","on":bool}`.

## Что сделать (два коммита)
**Коммит 1 — кодек.** `PhoneVoiceCodec` (RefCounted, только `static func`, без узлов): `TYPE_MIC := 1`, `TYPE_PEER := 2`, `HEADER_BYTES := 5`, `MAX_PAYLOAD := 4096`; `encode(type: int, seq: int, pcm: PackedByteArray) -> PackedByteArray` (seq по модулю 2^32; пустой или нечётный pcm, или > MAX_PAYLOAD → пустой массив); `decode(bytes: PackedByteArray) -> Dictionary` — `{ok: bool, type: int, seq: int, pcm: PackedByteArray}` (ok=false при размере < 6, нечётной длине полезной части, > MAX_PAYLOAD, неизвестном типе); `samples_per_chunk(rate: int, ms: int = 20) -> int`.
Тест `phone_voice_codec_test.gd`: круговой encode→decode; границы длины; wrap seq; образцы hex из `phone_frames.json` раздела `binary` (`voice_mic_hex`, `voice_peer_hex`: `hex_decode()`, сверить тип/seq/отсчёты и что encode даёт ровно этот hex).
Проверка: `dev.sh test phone_voice_codec_test` → зелёный.

**Коммит 2 — связь.** В `RemotePhoneLink`:
1. Приём: в `advance` пакет текстовый (`_peer.was_string_packet()`) → как сейчас в `on_frame(_parse(...))`; бинарный → `_on_binary(packet)`: `PhoneVoiceCodec.decode`, принимаем только `TYPE_PEER` и только когда голос включён (`voice_active()`), остальное молча отбрасываем и считаем в `voice_dropped` (int); годный → сигнал `voice_frame_received(seq: int, pcm: PackedByteArray)`. В списке `_joining` (до hello) бинарный пакет — закрыть с `CLOSE_BAD_HELLO`.
2. `on_frame` тип `voice`: `on` и `rate` (по умолчанию 44100; допустимо 8000…48000, иначе кадр игнорировать); запомнить `_voice_on/_voice_rate`, сигнал `voice_requested(on: bool, rate: int)`. Если состояние не изменилось и rate тот же — сигнал не повторять.
3. `func voice_active() -> bool`, `func voice_rate() -> int`.
4. Команды очков: `send_voice_ready(on: bool)` (JSON `voice_ready`); `send_voice_chunk(pcm: PackedByteArray) -> bool` — бинарный кадр `TYPE_MIC`, счётчик seq своя (`_voice_seq`, с 0, сбрасывается при каждом `voice{on:true}`), false если нет телефона или кодек вернул пусто (`_peer.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)`).
5. Сброс: `_drop_peer` и `stop()`/`pause()` — если голос был включён, обнулить и испустить `voice_requested(false, rate)` (чтобы узел голоса погасил микрофон).
6. Лимит 256 КБ кадра остаётся; бинарный пакет > `MAX_FRAME_BYTES` закрывает соединение кодом 1009, как и текстовый.
Тесты в `remote_phone_link_test.gd` (по образцу `_online_phone`, `_say`, `_pump`; бинарные клиентские кадры — `ws.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)`): `voice{on:true,rate}` даёт `voice_requested(true, rate)` и `voice_active()`; неверный rate игнорируется; бинарный TYPE_PEER доходит сигналом, TYPE_MIC и мусор — нет, `voice_dropped` растёт; чанк микрофона доходит клиенту с типом 1 и возрастающим seq; `voice_ready` уходит JSON; обрыв сбрасывает голос с `voice_requested(false, …)`; пауза — то же.
Проверка: `dev.sh test phone_voice_codec_test remote_phone_link_test fake_phone_test phone_client_test` → все зелёные (до правок: 18 / 25 / 20 в двух последних, без нового кодека).

## Приёмка
Два коммита, `git diff --stat` от стартового коммита — только файлы зоны. Отчёт ≤15 строк по шаблону; в отчёте — публичный API (сигналы и методы) одним списком.
