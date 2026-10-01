# VR-очки и софт для «Сети»: подбор конфигурации

Результат по [заданию](netrun-vr-hardware-brief.md). Дата исследования — 2026-10-01. Только чтение интернета: ни одно устройство
не проверялось руками. Всё, чего нет в источниках, помечено «неизвестно» или «предположение». Пометка «(в брифе)» — утверждение
из раздела 5 брифа, здесь повторно перепроверено только там, где указан новый источник.

> **Решение владельца (октябрь 2026):** берём **обычную Pico 4**, не Ultra и не Enterprise. Рекомендация ниже про
> Ultra Enterprise не принята; версии софта (Godot 4.7.2 и др.) остаются в силе. Досследование обычной Pico 4 — раздел 10.

## 1. Рекомендация одной строкой

**Pico 4 Ultra Enterprise (12 ГБ / 256 ГБ), Godot 4.7.2-stable + OpenXR Vendors 5.1.0 (по необходимости), Gradle-экспорт на
JDK 17 / build-tools 35.0.1 / platform android-35 / NDK 28.1.13356709, рендерер Mobile (Vulkan) с запасным Compatibility, прошивку
закрепить на версии, на которой пройдёт чек-лист из п. 7**; на прототип купить 2 экземпляра. **Цена не укладывается в ориентир
владельца (П1) в разы** — см. п. 3 и вопросы в п. 9.

## 2. Таблица конфигурации

| Компонент | Выбор | Почему | Источник |
|---|---|---|---|
| Очки | Pico 4 Ultra Enterprise, 12 ГБ / 256 ГБ (Snapdragon XR2 Gen 2, 2160×2160 на глаз, 90 Гц по спецификации, Wi-Fi 7, цветной passthrough 2×32 МП) | Только Enterprise-версия поддерживает сторонний MDM, киоск Pico и автозапуск по загрузке; у потребительской их блокирует система. Ultra Enterprise — рекомендуемая Pico замена Pico 4 Enterprise для новых парков | [specs](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs), [ArborXR](https://help.arborxr.com/en/articles/8342487-can-arborxr-be-installed-on-pico-consumer-headsets), [pico-webxr-kiosk](https://github.com/robinhuse/pico-webxr-kiosk), [VR Expert](https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/) |
| Прошивка (Pico OS) | Версию не закрепляем по номеру заранее: на момент исследования в открытых источниках видна ветка 5.x (5.14.x, август 2025); 6.x не найдено. Закрепить ту, на которой пройдут проверки п. 7, и поставить её на весь парк | Обновление офлайн возможно только вверх (понижать нельзя), поэтому целевая версия = самая новая из партии | [pico4.wiki OTA](https://pico4.wiki/guides/ota/), [Pico community](https://www.picoxr.com/global/software/pico-os) |
| Godot | **4.7.2-stable** (18.08.2026) — последний стабильный; запасной вариант 4.6.3-stable. Шаблоны экспорта той же версии скачать дома | Плагин 5.x требует Godot 4.6+; в 4.7 заявлено улучшение фовеального рендеринга на Vulkan (subsampled images). Для 4.7.x есть ошибки Mobile-рендерера на отдельных Android-телефонах (не очки) — проверить на очках | [релизы Godot](https://github.com/godotengine/godot/releases), [Godot 4.7](https://godotengine.org/releases/4.7/), [issue #123376](https://github.com/godotengine/godot/issues/123376) |
| Плагин OpenXR Vendors | **5.1.0-stable** (19.05.2026, только Godot 4.6+). Для MVP на стандартном OpenXR плагин **не обязателен**; нужен, если потребуется passthrough (П4) или вендорские расширения Pico | На Pico passthrough в Godot заработал только с плагином 4.0.0-rc1+ (конфликт core alpha blend и FB passthrough). Плагин требует Gradle-сборку и один вендор на шаблон экспорта | [releases](https://github.com/GodotVR/godot_openxr_vendors/releases), [установка](https://godotvr.github.io/godot_openxr_vendors/getting-started/installation.html), [форум](https://forum.godotengine.org/t/no-passthrough-option-on-pico-4-using-openxr-vendor-plugin-godot-v4-4-1-stable/108379) |
| JDK | OpenJDK 17 (Temurin) | Требование документации Godot 4.7 | [Godot: экспорт на Android](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html) |
| Android SDK | platform-tools, cmdline-tools/latest, **build-tools 35.0.1, platforms android-35**, cmake 3.10.2.4988404 | Версии из инструкции Godot 4.7. В ветке master (будущая 4.8) уже build-tools 36.1.0 / android-36 — не брать | то же (исходник docs 4.7) |
| NDK | **r28b (28.1.13356709)** | То же. В master — NDK 29.0.14206865, не брать | то же |
| Рендерер | **Mobile** (Vulkan); если на очках проблемы с драйвером — Compatibility. Решение принимает чек-лист п. 7 | Документация Godot рекомендует Mobile для автономных очков; ubershaders и предкомпиляция конвейеров только в Mobile/Forward+. На Pico стабильность Vulkan в Godot — неизвестно | [Setting up XR](https://github.com/godotengine/godot-docs/blob/master/tutorials/xr/setting_up_xr.rst), [Pipeline compilations](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) |
| Частота / разрешение / фовеация | Цель — 90 Гц (в спецификации Ultra Enterprise указано только 90 Гц; доступность 72 Гц на этой модели неизвестна). Рендер-разрешение по спецификации 1920×1920 на глаз; множитель render target подбирать на устройстве. Фовеация — включить фиксированную (Vulkan FDM, Godot 4.6+), проверить на Pico; eye-tracked фовеации у Ultra Enterprise нет (у модели нет eye tracking в найденной спецификации) | В Godot 4.6+ фовеация на Vulkan/Android есть, но открыты баги на Quest (#112988, #112834, #113778); работа на Pico не подтверждена | [spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs), [issue #102780](https://github.com/godotengine/godot/issues/102780), [#112988](https://github.com/godotengine/godot/issues/112988) |
| Киоск / парк | Основной путь — штатный киоск Pico: (а) PICO Business Suite (бесплатно, ПК-программа в одной Wi-Fi-сети, вход в Business-аккаунт) или (б) Device Manager (платный, облачный). Запасной — самодельные скрипты/лаунчер (PicoKiosk) | Что из этого работает полностью офлайн после настройки — **неизвестно** (см. Ж3/Ж8) | [Business Suite](https://business.picoxr.com/global/software/business-suite), [цены](https://business.picoxr.com/global/pricing), [VR Expert](https://knowledge.vr-expert.com/kb/how-to-use-the-pico-business-suite-on-the-pico-4-enterprise/), [PicoKiosk](https://github.com/it03lab-ops/PicoKiosk) |
| Аксессуары | Контроллеры питаются 2×AA; ставить аккумуляторы NiMH AA; запасные контроллеры L/R продаются отдельно; внешний аккумулятор-ремень (BOBOVR P4U, 10000 мАч) по желанию | Контроллеры не заряжаются сами | [spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs), [VR Expert](https://vr-expert.com/en-us/accessories/vr-accessories/pico-4-ultra-controller-l/), [BOBOVR](https://www.bobovr.com/products/bobovr-p4u) |

## 3. Проверка требований

### Жёсткие

| # | Статус | Основание |
|---|---|---|
| Ж1 | **Выполняется** | Автономные очки Android, 6DoF, 4 камеры трекинга, 2 контроллера ([spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs)) |
| Ж2 | **Выполняется** (в основном) | Enterprise OS заявляет поддержку OpenXR; экспорт Godot на Android-очки без плагина работает (в брифе); плагин нужен лишь для вендорских функций ([VR Expert](https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/)) |
| Ж3 | **Неизвестно** | Нет источника про многодневную работу без интернета и без проверки аккаунта. Первичная настройка Enterprise требует Wi-Fi, обновления и вход в Pico Business-аккаунт ([VR Expert](https://knowledge.vr-expert.com/kb/getting-started-with-the-pico-4-enterprise/)). Обратите внимание: ArborXR заявляет офлайн-режим для Pico ([ArborXR](https://arborxr.com/supported-devices/pico)), но это отдельный платный продукт и детали неизвестны |
| Ж4 | **Выполняется частично** | Активация, аккаунт и обновление делаются один раз с интернетом (источник выше). Прошивка ставится офлайн из папки `dload` или через recovery и `adb sideload` ([pico4.wiki](https://pico4.wiki/guides/ota/)); но только вверх, понижать нельзя. Режим разработчика: 7 тапов по версии ПО в Настройках, затем «Developer» → USB Debug ([ArborXR](https://help.arborxr.com/en/articles/10771596-developer-mode-usb-debugging-on-pico-4-ultra-enterprise)); требования интернета в источнике не указаны, на устройстве проверить |
| Ж5 | **Неизвестно** | Источников о поведении Pico при Wi-Fi «без интернета» не найдено. Предположение: UDP в локальной сети работает (стандартный Android); проверка обязательна. Есть настройка «Keep Wi-Fi connected in sleep mode» ([ArborXR](https://help.arborxr.com/en/articles/6630022-configure-pico-system-settings)) |
| Ж6 | **Выполняется** | Установка APK через adb и режим разработчика ([Matts Digital](https://knowledge.matts-digital.com/en/virtual-reality/pico/pico-4-ultra-enterprise/how-to-install-an-app-on-the-pico-4-ultra-enterprise/)) |
| Ж7 | **Неизвестно** | Источников о сохранении контура после сна/перезагрузки/замены очков не найдено. Известно: при первом включении выбирается Quick Setup (круг, сидя/стоя) или Custom ([VR Expert](https://knowledge.vr-expert.com/kb/how-to-set-up-a-boundary-on-the-pico-4-enterprise/)); границу в Enterprise можно отключить конфигурацией «только для стационарных сценариев» ([ArborXR](https://help.arborxr.com/en/articles/6630022-configure-pico-system-settings)); в описании Enterprise упомянут «общий play space» между очками (источник — [komete-xr](https://komete-xr.com/en/products/pico-4-ultra-enterprise), деталей нет) |
| Ж8 | **Неизвестно** | Киоск запускает приложение при загрузке ([Business Suite](https://business.picoxr.com/global/software/business-suite)); возврат после сна источниками не подтверждён. Автозапуск по загрузке на потребительской версии заблокирован системой ([pico-webxr-kiosk](https://github.com/robinhuse/pico-webxr-kiosk)) |
| Ж9 | **Неизвестно** | Замеров Godot на Pico 4 Ultra не найдено. Чип XR2 Gen 2 мощнее Quest 2/Pico 4 по заявлению производителя (GPU +250% к первому поколению; [Pico](https://www.picoxr.com/global/about/newsroom/pico-4-ultra-enterprise)), предположение: простая сцена потянет; замерять |
| Ж10 | **Выполняется (с оговоркой)** | В России Ultra Enterprise у нескольких магазинов указан «в наличии» ([Vizzion](https://vizzion.ru/catalogs/vr_ar_equipment/avtonomnij-vr-shlem-pico-4-ultra-enterprise/)); возможность купить сразу 14 штук и одну прошивку на всех — не подтверждена. За рубежом на 12 ГБ у одного дилера ожидание декабря 2026 ([поиск](https://channelxr.com/products/pico-4-ultra-enterprise-vr-headset)) |

### Желательные

| # | Статус | Основание |
|---|---|---|
| П1 | **Не выполняется** | Цена Ultra Enterprise в РФ у найденных магазинов 135–200 тыс. ₽ (например 154 900 ₽ у [Vizzion](https://vizzion.ru/catalogs/vr_ar_equipment/avtonomnij-vr-shlem-pico-4-ultra-enterprise/)); в США 699 $ MSRP ([VR Expert](https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/)). Потребительская Ultra — около 60–69 тыс. ₽ ([Electrogor](https://www.electrogor.ru/shlemy-virtualnoi-realnosti/shlem-virtualnoi-realnosti-pico-4-ultra-256gb.html), на момент проверки «распродано»). Разница за Enterprise: поддерживаемый MDM, киоск и автозапуск по загрузке (Enterprise OS) |
| П2 | **Неизвестно** | 5770 мАч, зарядка 45 Вт ([spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs)); время работы официально не указано, вторичные источники — «около 3 ч» ([VR Expert](https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/)). Работа от внешнего питания сидя: батарея-ремень BOBOVR (сменяется на ходу), заряд во время игры — не проверено |
| П3 | **Неизвестно** | Данных по Ultra нет. Для Pico 4: трекинг теряется в темноте, от ИК и перед голыми стенами (в брифе, [Reddit](https://www.reddit.com/r/PicoXR/comments/11q9jj5/new_pico_4_wont_track_anymore_limited_terrain/)); у Ultra дополнительно 4 камеры окружения + iToF ([spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs)) — предположение, что лучше, проверять |
| П4 | **Частично** | Железо есть (цветной passthrough). В Godot на Pico работает через плагин ≥ 4.0.0-rc1 ([форум](https://forum.godotengine.org/t/no-passthrough-option-on-pico-4-using-openxr-vendor-plugin-godot-v4-4-1-stable/108379)); с 5.1.0 на Ultra — не проверено |
| П5 | **Выполняется** (предположение) | Модель 2024 года, позиционируется как текущая замена; срок поддержки производитель не публикует ([VR Expert](https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/)) |
| П6 | **Неизвестно** | Два стереодинамика ([spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs)); громкость в шумной локации не измерена. Предположение: потребуются наушники |
| П7 | **Выполняется** | 2×AA в каждом контроллере, встроенного аккумулятора нет ([spec](https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs)); время работы на комплекте — неизвестно. Решение: NiMH AA, запасные комплекты |

## 4. Альтернативы и почему отказались

- **Потребительская Pico 4 Ultra (около 60–69 тыс. ₽).** Сторонний MDM на неё не ставится (Pico блокирует), автозапуск по загрузке системой перехватывается, киоска нет ([ArborXR](https://help.arborxr.com/en/articles/8342487-can-arborxr-be-installed-on-pico-consumer-headsets), [pico-webxr-kiosk](https://github.com/robinhuse/pico-webxr-kiosk)). Режим разработчика и adb работают. Самодельный PicoKiosk (замена лаунчера + adb-блокировка выходов) протестирован на Pico 4, на Ultra — не заявлен; готовых сборок нет, нужна сборка из исходников ([PicoKiosk](https://github.com/it03lab-ops/PicoKiosk)). Остаётся как **план Б для снижения цены**, если проверка п. 7 покажет, что Ж7/Ж8 решаются без Enterprise. Жёсткое требование Ж8 здесь под вопросом.
- **Pico 4 Enterprise (не Ultra): 95–137 тыс. ₽,** Snapdragon XR2 первого поколения, 8 ГБ, батарея 5300 мАч, 72/90 Гц, eye/face tracking ([pico-russia.ru](https://pico-russia.ru/product/avtonomnyj-vr-shlem-pico-4-enterprise/)). Дешевле, но старый чип (Ж9 тяжелее), по результатам поиска (один вторичный источник) для нового парка в 2026 не рекомендуется — Pico предлагает Ultra Enterprise. Не выбираем, но если в наличии дешевле — подходит как вариант; тогда прототип обязан быть тоже этой моделью.
- **Pico 4 (не Ultra, потребительская).** Цена и наличие не исследовались — неизвестно. Те же ограничения по автозапуску, что у потребительской Ultra.
- **Другие марки.** Не рассматривали: Pico-линейка не нарушает ни одного жёсткого требования достоверно (Ж3, Ж5, Ж7, Ж8 — неизвестны, а не нарушены). Если прототип на Ж3 провалится, придётся пересмотреть.

## 5. Порядок подготовки парка

Это план; всё, что стоит под знаком «?», подтверждается чек-листом п. 7.

**Дома, с интернетом (один раз на каждые очки):**
1. Включить, выбрать язык, подключить Wi-Fi, войти в Pico Business-аккаунт (аккаунт создаётся на business.picoxr.com).
2. Обновить прошивку до выбранной версии. Если у экземпляров разные версии — подтянуть все до самой новой; понизить нельзя.
3. Включить режим разработчика (7 тапов по версии ПО → Developer → USB Debug); отключить сон: Настройки → Developer → System → Power Policy → System Sleep Timeout = Never (шаги найдены для Neo 3 ([VR Expert](https://knowledge.vr-expert.com/kb/how-to-turn-off-the-sleep-mode-of-the-pico-neo-3/)); на Ultra Enterprise меню может отличаться).
4. Скачать шаблоны экспорта Godot 4.7.2 и плагин 5.1.0 (если нужен), Android SDK/NDK/JDK по таблице п. 2 — на ПК площадки они понадобятся офлайн.
5. Настроить киоск: Business Suite (ПК и очки в одной Wi-Fi-сети; ПК выкладывает приложение, очки запускаются в него) или, при необходимости, Device Manager. Отметить, что нужно ли потом интернет — неизвестно.

**Офлайн, на площадке:**
6. APK ставится по USB-C и `adb install -r` (при включённом USB Debug; режим «File Transfer»).
7. Боундари: один раз на стойке (сидя), затем проверка п. 7 (после сна/перезагрузки/замены).
8. Обновления отключить: без интернета очки сами ничего не скачают (предположение); штатный способ закрепить версию — Device Manager/ArborXR (платно, облако) ([ArborXR](https://help.arborxr.com/en/articles/6415606-manage-pico-neo-3-pro-pico-g3-and-pico-4-enterprise-operating-system-updates)). Простой обходной путь: держать очки только в локальной сети без выхода в интернет.

## 6. Закупка

Цены РФ — по найденным предложениям на 2026-10-01; точные цены и наличие 14 штук нужно уточнить у продавца.

| Позиция | Прототип | Парк (13–15) | Ориентировочная цена | Где |
|---|---|---|---|---|
| Pico 4 Ultra Enterprise 12/256 | 2 | 14 (10 + 4 запас) | 135–200 тыс. ₽ (типично 155 тыс.); 699 $ MSRP | Vizzion, picoxr-ru.ru, virtuality.club и др. |
| Контроллеры (запасные, пара) | 1 | 2–3 | неизвестно | VR Expert, komete-xr |
| NiMH AA, комплекты и зарядное | 8 шт + зарядка | на каждый контроллер 2 комплекта | неизвестно | любая розница |
| Зарядные 45 Вт (PD 3.0/QC 4.0) и кабели USB-C | 2 | 14 + запас | неизвестно | любая розница |
| Сменные накладки/силиконовые чехлы | 2 | 14 | неизвестно | комплектные сменные в комплекте очков; запас — неизвестно |
| Проставки для очков для зрения | 2 | по потребности | неизвестно | не исследовались |
| Батарея-ремень BOBOVR P4U | 1 (по желанию) | по необходимости | неизвестно | bobovr.com |
| ИК-подсветка | 0 | 0 | — | не нужна; ИК мешает трекингу (в брифе) |
| Device Manager (если выберем) | 2 | 14 | 99 $ / год / устройство (облачный) | [Pico](https://business.picoxr.com/global/pricing) |

Оценка бюджета на парк: 14 × 155 тыс. ₽ ≈ 2,2 млн ₽ — это примерно в 6–7 раз выше ориентира 20–25 тыс. ₽ за очки.

## 7. Чек-лист проверки на первых 1–2 очках

Каждый пункт отвечает на «неизвестно» из п. 3. Критерий успеха указан справа.

| # | Что сделать | Успех |
|---|---|---|
| 1 | Ж3. Включить очки без интернета (после домашней настройки), оставить на 3 дня включёнными/выключенными по расписанию, ежедневно запускать APK | Нет окон входа/проверки аккаунта, приложение запускается |
| 2 | Ж5. Подключить к UniFi без интернета, запустить клиент Godot, держать UDP-соединение с серверным ПК 30 минут | Нет автоотключения от сети, пакеты идут, переподключение после сна |
| 3 | Ж7. Настроить сидячий контур; затем: сон 10 минут, полная перезагрузка, подмена очков на запасные на том же месте | Контур сохранён (или найден рабочий путь: общий play space/отключение границы) |
| 4 | Ж8. Киоск/автозапуск: снять очки (сон), надеть; перезагрузить | Сразу попадаем в наше приложение, без системного меню |
| 5 | Ж8, потребительский вариант (если рассматриваем план Б): те же шаги на потребительской Ultra с PicoKiosk | Успех — те же результаты без Enterprise |
| 6 | Ж9. Простая сцена Godot со светящимися материалами: Mobile (Vulkan) и Compatibility; 72 и 90 Гц (какие доступны) | ≥ 72 кадров/с стабильно 30 мин, без крашей драйвера; выбираем рендерер по результату |
| 7 | Фовеация и множитель разрешения: включить, подобрать | Видимый выигрыш по кадру без артефактов (см. баги #112988, #112834) |
| 8 | Ж4/Ж6. Развернуть Android SDK/NDK/JDK и шаблоны офлайн; собрать APK; поставить по adb | Сборка без интернета, APK ставится |
| 9 | Ж4. Офлайн-обновление `dload` на второй экземпляр | Версии обоих совпали |
| 10 | П2. Запуск 30-минутной сцены, замер заряда; зарядка между забегами; игра от питания (если нужно) | Расход заряда за забег и скорость подзарядки зафиксированы |
| 11 | П3. Проверка трекинга в тёмной комнате с неоновой подсветкой на площадке | Нет потери трекинга за 30 минут |
| 12 | П4. Passthrough: плагин 5.1.0, включить, проверить на Ultra | Картинка комнаты по запросу, возврат в игру |
| 13 | П6. Звук во встроенных динамиках при шуме площадки | Слышно; иначе — выбрать наушники |
| 14 | П7. Время работы контроллеров на NiMH AA | Хватает на день ротации |

## 8. Источники

- Pico Ultra Enterprise, спецификации: <https://business.picoxr.com/global/products/pico4-ultra-enterprise/specs>
- Pico Business: Business Suite <https://business.picoxr.com/global/software/business-suite>, цены <https://business.picoxr.com/global/pricing>
- Pico OS: <https://www.picoxr.com/global/software/pico-os>; новость <https://www.picoxr.com/global/about/newsroom/pico-4-ultra-enterprise>
- Прошивка офлайн: <https://pico4.wiki/guides/ota/>
- Режим разработчика: <https://help.arborxr.com/en/articles/10771596-developer-mode-usb-debugging-on-pico-4-ultra-enterprise>
- Настройки системы Pico: <https://help.arborxr.com/en/articles/6630022-configure-pico-system-settings>
- MDM только на Enterprise: <https://help.arborxr.com/en/articles/8342487-can-arborxr-be-installed-on-pico-consumer-headsets>
- ArborXR Pico: <https://arborxr.com/supported-devices/pico>
- Автозапуск, потребительская против Enterprise: <https://github.com/robinhuse/pico-webxr-kiosk>
- PicoKiosk: <https://github.com/it03lab-ops/PicoKiosk>
- VR Expert (Enterprise): <https://knowledge.vr-expert.com/kb/getting-started-with-the-pico-4-enterprise/>, <https://knowledge.vr-expert.com/kb/how-to-use-the-pico-business-suite-on-the-pico-4-enterprise/>, <https://knowledge.vr-expert.com/kb/how-to-set-up-a-boundary-on-the-pico-4-enterprise/>, обзор <https://vrx.vr-expert.com/pico-4-ultra-enterprise-review-2026/>
- Matts Digital, установка приложения: <https://knowledge.matts-digital.com/en/virtual-reality/pico/pico-4-ultra-enterprise/how-to-install-an-app-on-the-pico-4-ultra-enterprise/>
- Komete (Ultra против Ultra Enterprise): <https://komete-xr.com/en/blogs/infos/pico-4-ultra-vs-pico-4-ultra-entreprise>
- Цены РФ: <https://vizzion.ru/catalogs/vr_ar_equipment/avtonomnij-vr-shlem-pico-4-ultra-enterprise/>, <https://www.electrogor.ru/shlemy-virtualnoi-realnosti/shlem-virtualnoi-realnosti-pico-4-ultra-256gb.html>, <https://pico-russia.ru/product/avtonomnyj-vr-shlem-pico-4-enterprise/>
- Контроллеры/аксессуары: <https://vr-expert.com/en-us/accessories/vr-accessories/pico-4-ultra-controller-l/>, <https://www.bobovr.com/products/bobovr-p4u>
- Godot: релизы <https://github.com/godotengine/godot/releases>, 4.7 <https://godotengine.org/releases/4.7/>, экспорт Android <https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html>, настройка XR <https://github.com/godotengine/godot-docs/blob/master/tutorials/xr/setting_up_xr.rst>, предкомпиляция <https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html>
- Плагин: <https://github.com/GodotVR/godot_openxr_vendors>, установка <https://godotvr.github.io/godot_openxr_vendors/getting-started/installation.html>, passthrough на Pico <https://forum.godotengine.org/t/no-passthrough-option-on-pico-4-using-openxr-vendor-plugin-godot-v4-4-1-stable/108379>
- Фовеация Godot: <https://github.com/godotengine/godot/issues/102780>, <https://github.com/godotengine/godot/issues/112988>, <https://github.com/godotengine/godot/issues/112834>, <https://github.com/godotengine/godot/issues/113778>
- Трекинг в темноте: <https://www.reddit.com/r/PicoXR/comments/11q9jj5/new_pico_4_wont_track_anymore_limited_terrain/>, <https://vrcasts.com/guides/vr-low-light-tracking-tips/>

## 9. Вопросы владельцу

1. Цена. Pico с поддержкой киоска стоит 135–200 тыс. ₽ за штуку (парк ≈ 2,2 млн ₽), потребительская Ultra — около 60–69 тыс. ₽ (≈ 0,9 млн ₽ на 14), но без штатного автозапуска. Ориентир 20–25 тыс. ₽ недостижим ни в одном варианте. Что важнее: бюджет или «надел и играешь» (Ж8)?
2. Готовы ли вы платить за Device Manager (≈ 99 $ / год / очки, облачный) или предпочитаете бесплатный Business Suite и самодельные скрипты?
3. Разрешено ли купить сначала 2 Ultra Enterprise и 1 потребительскую Ultra для сравнения Ж8?
