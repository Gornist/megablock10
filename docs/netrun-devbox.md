# Настройка машины разработки для netrun (Ubuntu 24.04 LTS Desktop)

Машина разработки собирает приложение, эмулятор и мир (Godot), запускает стенд e2e и сервер Моста. Конфигурация: i7-9700T, 16 ГБ оперативной памяти, GTX 1650, Ubuntu 24.04 LTS Desktop.

## До скрипта (вручную)

1. **BIOS: включите VT-x (Intel VMX)** — для KVM и эмулятора.
2. **Ubuntu 24.04 LTS Desktop минимальная установка** (без дополнительных приложений).
3. **Swap 8–16 ГБ** — для сборок и роботестов.
4. **Постоянный IP** (192.168.X.Y; DHCP с резервированием или статический) — для подключения по SSH из Claude Code.
5. **SSH-ключ с Mac** (если подключаетесь из Claude Code):
   ```bash
   # На Mac: скопируйте открытый ключ
   cat ~/.ssh/id_ed25519.pub
   
   # На машине разработки: добавьте в ~/.ssh/authorized_keys
   mkdir -p ~/.ssh
   echo "ваш_публичный_ключ_с_Mac" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

## Запуск скрипта

```bash
bash scripts/devbox-setup.sh                    # все шаги
bash scripts/devbox-setup.sh --no-nvidia        # без драйвера NVIDIA
bash scripts/devbox-setup.sh --android-only     # только Android SDK и эмуляторы
```

Скрипт идемпотентный: повторный запуск ничего не ломает. Длительность: 30–50 минут (зависит от интернета).

## После скрипта

Добавьте в `~/.bashrc` или `~/.zshrc`:

```bash
export ANDROID_HOME=$HOME/android-sdk
export ANDROID_SDK_ROOT=$HOME/android-sdk
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
export PATH=$HOME/.local/bin:$PATH
```

Новый вход и проверка:

```bash
source ~/.bashrc
id -nG | grep kvm                              # убедитесь в членстве в группе kvm
java -version                                  # должна быть 21
sdkmanager --list_installed | head -10         # должны быть android-35, build-tools-35.0.1
godot --version                                # должна быть Godot 4.7.2
```

## Подключение из Claude Code (по SSH)

1. **Узнайте IP машины разработки:**
   ```bash
   hostname -I
   ```

2. **В Claude Code:** Claude Code > Settings > SSH > New connection:
   - Host: `192.168.X.Y` (IP машины)
   - User: (ваш пользователь на машине, обычно первый, кто логинился)
   - Port: 22 (по умолчанию)
   - Key: (выберите приватный ключ Ed25519)

3. **Сессия откроется в `$HOME`, абсолютные пути работают как обычно.**

## Запуск стенда e2e на машине разработки

```bash
cd ~/megablock10
scripts/e2e/up.sh              # запуск эмуляторов, сервера, APK (~3 мин)
scripts/e2e/run-all.sh         # все сценарии (проверка логики)
scripts/e2e/down.sh            # остановка
```

На второй и следующие запуски используйте `--keep-data`:

```bash
scripts/e2e/up.sh --keep-data  # не сбрасывать БД сервера
```

Если эмулятор завис, перезагрузитесь:

```bash
scripts/e2e/down.sh
pkill -f emulator || true
scripts/e2e/up.sh
```

## Запуск сервера Моста и мира (Godot)

На машине разработки (локально, без эмуляторов):

### 1. Сервер Моста (Kotlin + :kit)

```bash
cd ~/megablock10
./gradlew :netrun-bridge:test :netrun-bridge:detekt  # проверка
java -jar netrun-bridge/build/libs/*.jar             # запуск сервера (если собран)
```

Или из Claude Code по SSH.

### 2. Сервер мира (Godot headless)

```bash
cd ~/megablock10/netrun
godot --headless -- --tokens=t1:alice,t2:bob --exit-after=300
```

### 3. Плоская отладочная сборка (локально, с окном)

```bash
cd ~/megablock10/netrun
godot -- --flat --host=127.0.0.1 --port=7777 --token=t1
```

Управление: W/A/S/D движение, мышь поворот, левый клик взятие предметов.

## Диагностика

### Эмулятор не стартует

```bash
# Список запущенных
adb devices

# Принудительный перезапуск
adb -s emulator-5554 shell reboot
# или
emulator -avd Medium_Phone_API_35 -wipe-data &
```

### Нет интернета в эмуляторе (нормально)

Эмулятор подключен только к локальной сети (Wi-Fi 10.0.0.0/8). Интернет здесь не нужен.

### Java / gradle версия

```bash
java -version                    # должна быть 21
./gradlew --version              # Gradle 8.14+
```

### Память и диск

```bash
free -h                          # оперативная память (нужно ≥ 4 ГБ свободных)
df -h $HOME                      # диск (нужно ≥ 10 ГБ свободных для SDK и Godot)
```

## Файлы и пути

| Что | Где |
|---|---|
| Android SDK | `$ANDROID_HOME` (по умолчанию `$HOME/android-sdk`) |
| JDK 17 | `/usr/lib/jvm/temurin-17-jdk-amd64/bin/java` |
| JDK 21 | `/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (по умолчанию `JAVA_HOME`) |
| Godot 4.7.2 | `$HOME/.local/godot/godot-4.7.2-stable` (симлинк `~/.local/bin/godot`) |
| Шаблоны Godot | `$HOME/.local/share/godot/export_templates/4.7.2.stable/` |
| AVD эмуляторов | `$HOME/.android/avd/` (Medium_Phone_API_35.avd, Second_API_35.avd) |
| Логи эмулятора | `$HOME/.android/avd/Medium_Phone_API_35.avd/` (файлы logs в конфиге) |
| Репозиторий | `$HOME/megablock10` (по умолчанию, если установлено) |
