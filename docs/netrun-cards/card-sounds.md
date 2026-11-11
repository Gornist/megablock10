# Карточка A: звуки телефона в очках (PhoneSounds)

**Цель:** когда телефон просит звук (`sound_requested` у `RemotePhoneLink`), очки играют его в гарнитуре: рингтон и дозвон — петлёй, сообщение — один раз.
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-sounds`, ветка `agent/phone-sounds` (от `agent/phone-link-remote`). На devbox копия — `~/wt-phone-sounds` (имя даёт `dev.sh`).

## Зона записи (только это)
- `netrun/client/phone_sounds.gd` (новый, `class_name PhoneSounds extends Node`)
- `netrun/client/audio/phone/cyberpunk_ring.mp3`, `cp77_dial_tone.mp3`, `cyberpunk_message.mp3` (новые, копии из git, см. ниже) и их `*.mp3.import`
- `netrun/tests/phone_sounds_test.gd` (новый)
НЕ трогать: `proto_client.gd`, `world_ui.gd`, `remote_phone_link.gd`, любые другие (подключение — другая задача).

## Досье
- Сигнал: `netrun/client/remote_phone_link.gd`, `signal sound_requested(kind: String)` — значения `ring` | `ringback` | `message` | `stop` (список — константа `SOUND_KINDS` там же). `stop` приходит и при обрыве телефона.
- Файлы звуков берутся из приложения: `git show HEAD:app/src/main/res/raw/<имя>` (HEAD уже содержит их; копируй через `git show … > файл`, не из чужих папок): `cyberpunk_ring.mp3` (15,75 с, петля), `cp77_dial_tone.mp3` (1,67 с, петля), `cyberpunk_message.mp3` (1,07 с, одиночный). mp3, 44,1 кГц, стерео.
- Как играет аудио соседний код — `netrun/client/audio/` (`tone_synth.gd`, `ice_audio.gd`, `trace_audio.gd`): смотри только стиль создания `AudioStreamPlayer`; микшерной шины отдельной не заводим (Master).
- Godot 4.7: `AudioStreamMP3.loop` (bool) включает петлю; `AudioStreamPlayer.play()/stop()`, свойство `playing`.

## Что сделать (один коммит)
1. Скопировать три mp3 в `netrun/client/audio/phone/`.
2. `PhoneSounds`:
   - `func bind(link: RemotePhoneLink) -> void` — подписаться на `sound_requested` (повторный `bind` на другую связь отписывает прежнюю).
   - `func play(kind: String) -> void` — `ring`: запустить рингтон-петлю и остановить дозвон; `ringback`: дозвон-петлю и остановить рингтон; `message`: проиграть одиночный (петли не трогает, не обрывает предыдущий такой же — просто перезапуск); `stop`: остановить обе петли (одиночный доигрывает); неизвестный `kind` — игнор без ошибки. Повторный `ring` при уже играющем рингтоне петлю не перезапускает.
   - `func is_playing(kind: String) -> bool` для `ring`/`ringback`/`message`.
   - Три `AudioStreamPlayer` создаются в `_ready`/`_init` и кладутся детьми; петли — `loop = true` на отдельном экземпляре стрима (ресурс из `load()` общий: `duplicate()` перед включением петли, иначе у `message` тоже поменяется).
   - Громкость — константы вверху файла (`VOLUME_DB_RING := -6.0` и т. п.), комментарий зачем.
3. `netrun/tests/phone_sounds_test.gd` (gdUnit4, как соседние `*_test.gd`): вручную собрать `RemotePhoneLink.new()` без сети (`start` не вызывать), `bind`, дёргать `link.on_frame({"t":"sound","kind":"ring"})` и проверять `is_playing`; кейсы: ring→играет; ringback вместо ring→ring остановлен, ringback играет; stop→обе стоят; message не останавливает петлю; неизвестный kind ничего не меняет; повторный bind другой связи — старая больше не управляет; стрим message не зациклен, ring/ringback зациклены.
   В headless-прогоне аудио-драйвер «Dummy»: если `playing` у `AudioStreamPlayer` в нём не становится true, считай состояние собственным флагом в `PhoneSounds` (и скажи об этом в отчёте).
4. Прогон: `netrun/tools/dev.sh test phone_sounds_test remote_phone_link_test` → оба зелёные (до правок `remote_phone_link_test`: 16 тестов).
5. Импорт: после прогона забери созданные на devbox `*.mp3.import` в свою worktree: `scp devbox:wt-phone-sounds/netrun/client/audio/phone/'*.mp3.import' netrun/client/audio/phone/` и добавь в коммит (так принято: у остальных ассетов `.import` в git).
6. Коммит: `git add` явными путями (все файлы зоны). Сообщение: что и почему (зачем в очках звуки телефона).

## Приёмка
`dev.sh test phone_sounds_test remote_phone_link_test` → ок; `git diff --stat HEAD~1` — только файлы зоны (4 + 3 mp3 + 3 import); отчёт по шаблону.
