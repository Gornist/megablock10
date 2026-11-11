# Карточка G: микрофон в сборке очков — настройки проекта, экспорт и выдача разрешения

**Цель:** APK очков запрашивает у системы микрофон и аудиодрайвер Godot открывает вход; `pico.sh install` сам выдаёт `RECORD_AUDIO` (без диалога внутри VR).
**Правила исполнителя:** `/private/tmp/claude-501/-Users-peachbite-Developer-megablock10/b5e593da-1b32-40c7-b757-4bc3f658fdd5/scratchpad/cards/rules-godot.md` — прочти первым.
**Worktree и ветка:** `/Users/peachbite/Developer/megablock10-wt/phone-voice-perm`, ветка `agent/phone-voice-perm` (от `agent/phone-voice-contract`). Копия на devbox — `~/wt-phone-voice-perm`.

## Зона записи (только это)
`netrun/project.godot`, `netrun/export_presets.cfg`, `netrun/tools/pico.sh`, `netrun/tests/voice_settings_test.gd` (новый, + `.gd.uid`).
НЕ трогать: `remote_phone_link.gd`, `proto_client.gd`, деку, документы. Очки и adb к очкам НЕ запускать (очки у владельца): проверка `pico.sh` — только `bash -n` и чтение глазами.

## Досье
- `netrun/export_presets.cfg`: ~строка 37 `permissions/internet=true`, `permissions/access_network_state=true` — рядом в этом же пресете «Client Pico 4 (Android)» нужен `permissions/record_audio=true` (в Godot 4.7 имя опции пресета — уточни по `grep -rn "record_audio" ` в документации/шаблонах Godot на devbox, `~/.local/share/godot/export_templates/4.7.2.stable/` или `godot --doc-tool`; не угадывай).
- `netrun/project.godot`: нужна настройка `audio/driver/enable_input=true` (секция `[audio]`, проверь имя в классе ProjectSettings из документации Godot 4.7.2 — через `ssh devbox` и `. ~/netrun-env.sh`, `godot --headless --doc-tool` не нужен: достаточно `strings`/grep по справке или запуск `godot --headless --path ~/wt-phone-voice-perm/netrun -s` скрипта, печатающего `ProjectSettings.has_setting`).
- `netrun/tools/pico.sh`: `cmd_install()` ~строка 77: `adb -s "$serial" install -r "$apk"`; `PACKAGE="com.megablok10.netrun"` вверху.

## Что сделать (один коммит)
1. `project.godot`: `audio/driver/enable_input=true`.
2. `export_presets.cfg`: `permissions/record_audio=true` в пресете очков (только в нём; пресет сервера и другие не трогать).
3. `pico.sh install`: после успешной установки выдать разрешение `adb -s "$serial" shell pm grant "$PACKAGE" android.permission.RECORD_AUDIO`; ошибка выдачи — предупреждение строкой, не провал установки (код возврата установки сохранить); в справке `install` одной строкой: «выдаёт RECORD_AUDIO (микрофон для голоса в звонке)».
4. `netrun/tests/voice_settings_test.gd` (gdUnit4): `ProjectSettings.get_setting("audio/driver/enable_input")` истинно; `export_presets.cfg` (прочитать `ConfigFile`/текст) содержит `permissions/record_audio=true` в пресете с именем «Client Pico 4 (Android)» и НЕ содержит его в других пресетах.
Проверка: `dev.sh test voice_settings_test phone_client_test` → зелёные; `bash -n netrun/tools/pico.sh` → ок.

## Приёмка
`git diff --stat` — только файлы зоны. Отчёт ≤15 строк по шаблону; в отчёте — точные имена найденных настроек и откуда они взяты.
