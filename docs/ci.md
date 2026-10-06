# CI: конвейер

## Раннер на devbox

Зачем: тяжёлый e2e (на облаке ≈17 мин) идёт на devbox — там тёплый кэш Gradle, готовые AVD и Android SDK (`~/android-sdk`).
Скрипт — `scripts/devbox-runner.sh install|status|remove` (с Mac, всё через `ssh devbox`).

### Установка (делает владелец)

```
gh api -X POST repos/Gornist/megablock10/actions/runners/registration-token -q .token | scripts/devbox-runner.sh install
scripts/devbox-runner.sh status        # RUNNER online (сервис: active)
```

Токен идёт только по stdin (не аргумент, не журнал, не чат). Скрипт качает последний `actions/runner` linux-x64, сверяет sha256
из описания релиза, ставит в `~/actions-runner`, регистрирует с меткой `devbox` и запускает как systemd **user**-сервис
`actions-runner` (sudo без пароля на devbox нет — `svc.sh` не годится). Снять: `gh api -X POST …/runners/remove-token -q .token | scripts/devbox-runner.sh remove`.

**Linger.** На devbox сейчас `Linger=no`: user-сервисы живут, пока есть сессия пользователя `nick` (на devbox GNOME-сессия на :0 — обычно
есть). Чтобы раннер переживал выход/перезагрузку без входа, владелец один раз выполняет на devbox: `sudo loginctl enable-linger nick`.

### Безопасность (репозиторий публичный)

Чужой PR на self-hosted раннере = исполнение чужого кода на машине владельца. Поэтому:
- job на раннере только при `github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository`
  (то есть push, schedule, dispatch и PR из этого же репозитория); форки — на `ubuntu-latest` или никак;
- Settings → Actions → General → Fork pull request workflows: **Require approval for all outside collaborators**;
- раннер не под root, секретов с правом записи в `main` на devbox нет; на devbox ничего ценнее рабочих копий не держим.

### Очередь: один `flock` с dbx.sh

`scripts/dbx.sh` берёт `flock -w 2700` на fd 9 файла `~/.dbx.lock`; flock — блокировка на файл, поэтому любой процесс, открывший
тот же файл, встаёт в ту же очередь. Шаг workflow обязан запускаться так: `flock -w 2700 ~/.dbx.lock <команда>`. Сам этот
`flock` и есть ожидание (job висит в очереди до 45 мин; больше — шаг падает кодом 1). Одна тяжёлая задача на машину сохраняется.

### Стенд e2e и риск

`scripts/e2e/up.sh` отказывает, если стенд занят (файл владельца), но агенты на devbox поднимают стенд **вне** `~/.dbx.lock` —
тогда job возьмёт замок, а `up.sh` откажет (job красный не из-за кода) или, хуже, помешает живому прогону агента. Нужна
**карточка Android-сессии** (её зона `scripts/e2e/`): `up.sh` и `run-all.sh` сами берут `flock -w 2700 ~/.dbx.lock` на время стенда,
после этого обёртка в job не нужна. Пока этого нет — перед запуском job проверять `scripts/e2e/up.sh --status`/файл владельца вручную.

### Пример job для e2e.yml

```yaml
e2e:
  if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
  runs-on: [self-hosted, devbox]
  timeout-minutes: 60
  steps:
    - uses: actions/checkout@v7
    # без установки SDK/AVD: они уже на devbox
    - run: flock -w 2700 ~/.dbx.lock bash -c 'scripts/e2e/up.sh && scripts/e2e/run-all.sh; rc=$?; scripts/e2e/down.sh; exit $rc'
```


### Откат

В `e2e.yml` вернуть `runs-on: ubuntu-latest` и шаги установки SDK/AVD; `scripts/devbox-runner.sh remove` снимает раннер.

## Защита `main` (ruleset 24602926, с 06.10)

Серверная страховка к хуку `guard-bash.sh` (хук видит только команды агентов): `main` нельзя удалить и перезаписать force-push,
обновление — только с зелёными `build` и `admin-web` (main.yml) и веткой, свежей относительно `main`. Исключение — роль admin
(владелец): `scripts/land.sh` работает как раньше. `e2e` и `netrun` не обязательные — запускаются не на каждый PR.
Смотреть: `gh api repos/Gornist/megablock10/rulesets/24602926`; выключить — Settings → Rules → Rulesets.
