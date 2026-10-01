# VR-очки и софт для «Сети»: подбор конфигурации

Результат по [заданию](netrun-vr-hardware-brief.md). Дата исследования — 2026-10-01. Только чтение интернета: ни одно устройство
не проверялось руками. Всё, чего нет в источниках, помечено «неизвестно» или «предположение». Пометка «(в брифе)» — утверждение
из раздела 5 брифа, здесь повторно перепроверено только там, где указан новый источник.

> **Решение владельца (октябрь 2026):** берём **обычную Pico 4**, не Ultra и не Enterprise. Рекомендация ниже про
> Ultra Enterprise не принята; версии софта (Godot 4.7.2 и др.) остаются в силе. Досследование обычной Pico 4 — раздел 10, он главнее разделов 2–7 и 9.

## 1. Рекомендация одной строкой

**Обычная Pico 4 (Snapdragon XR2 Gen 1, 8 ГБ, версия Global, 128 или 256 ГБ), Godot 4.7.2-stable (+ OpenXR Vendors 5.1.0 только
при необходимости), Gradle-экспорт на JDK 17 / build-tools 35.0.1 / platform android-35 / NDK 28.1.13356709, рендерер Mobile
(Vulkan) с запасным Compatibility, прошивку выровнять на самой новой из партии и закрепить офлайн (откат невозможен); на прототип
купить 2 экземпляра.** Версию CN не брать. Цена — около 36–65 тыс. ₽ за штуку (парк из 14 — примерно 0,5–0,9 млн ₽), П1
(20–25 тыс. ₽) не выполняется, но близко. Главный риск — Ж8 (возврат в приложение без Enterprise): штатного пути нет, самодельный
путь не подтверждён на устройстве, запасной вариант — помощник у стойки; подробности, таблица требований и порядок подготовки
парка — в разделе 10. Таблицы 2–7 ниже написаны под Ultra Enterprise: для обычной Pico 4 они уступают разделу 10, кроме строк
про Godot, JDK, SDK, NDK, рендерер.

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

## 10. Обычная Pico 4 (досследование)

Дата — 2026-10-01, только чтение интернета, на устройстве ничего не проверялось. Решение владельца — обычная Pico 4 (не Ultra, не
Enterprise) — не обсуждается. «Неизвестно» и «предположение» — не отказ, а то, что закрывает чек-лист п. 7 и п. 10.8.

### 10.1. Наличие, цены, версия

| Что | Данные | Источник |
|---|---|---|
| Варианты | 8 ГБ ОЗУ в обоих; 128 и 256 ГБ. Для нашего APK хватает 128 ГБ (предположение), разница в цене 4–10 тыс. ₽ | [iprofishop 128](https://iprofishop.ru/catalog/igrovye_pristavki/pico_vr/88818/), [portal-shop](https://portal-shop.com/catalog/vr_ochki/vr_shlemy/2277/) |
| 128 ГБ, РФ | 35 990 ₽ («в наличии», iprofishop); 54 990 ₽ («в наличии», Москва, offo); 50–55 тыс. ₽ («под заказ», tech-iq); 42 900 ₽ (распродано, electrogor) | [iprofishop](https://iprofishop.ru/catalog/igrovye_pristavki/pico_vr/88818/), [offo](https://offo.ru/catalog/shlem-virtualnoy-realnosti/shlem-vr-pico-4-4320x2160-128-gb-90-gts-bazovaya-global/), [tech-iq](https://tech-iq.ru/product/avtonomnyj-vr-shlem-pico-4-128-gb/), [electrogor](https://www.electrogor.ru/shlemy-virtualnoi-realnosti/shlem-virtualnoi-realnosti-pico-4-128gb.html) |
| 256 ГБ, РФ | 39 990 ₽ (iprofishop); 48 990 ₽ (под заказ, portal-shop); 57 900 ₽ (нет в наличии, formula-iq); 64 900–65 000 ₽ (под заказ, virtualnyeochki — **версия CN**, vr-zone) | [portal-shop](https://portal-shop.com/catalog/vr_ochki/vr_shlemy/2277/), [formula-iq](https://formula-iq.com/product-page/pico-4-256gb/), [virtualnyeochki](https://virtualnyeochki.ru/avtonomnyie-vr-ochki/avtonomnye-vr-ochki-pico/pico-neo-4-256-gb), [vr-zone](https://vr-zone.ru/avtonomnyy-vr-shlem-pico-4-256-gb/) |
| Б/у | **Неизвестно**: объявления (Авито и др.) не удалось прочитать | — |
| 13–15 одинаковых | **Неизвестно**: на страницах нет остатка по количеству, у большинства «под заказ». Нужен запрос поставщикам на 14 шт. и проверка, что все Global и из одной партии | — |
| Версия CN | Не брать. Pico Store и часть приложений у CN недоступны; при обновлении «по воздуху» CN остаётся CN; региональная смена через OTA невозможна; при некоторых региональных настройках блокируется Wi-Fi 5 ГГц. Для Ж5 (UniFi, 5 ГГц) это недопустимо | [vr180g](https://vr180g.com/pico/picochina.php?l=en), [pico4.wiki](https://pico4.wiki/guides/ota/) |
| Снятие с производства | Официального объявления не найдено; Pico 4 вышла в октябре 2022, Pico 5 по сообщениям отменена, преемник — Pico 4 Ultra | [MIXED](https://mixed-news.com/en/pico-5-canceled-report/), [Wikipedia](https://en.wikipedia.org/wiki/PICO_4) |
| Прошивка | В магазинах указана «PICO OS 5.0» (устарело). Сообщество: Global 5.13.3 (и CN 5.13.3 Beta). Более свежая — неизвестно. Версии по Android: Pico 4 — Android 10 (одна вторичная публикация, надёжность низкая) | [owomushi](https://owomushi.com/Pico-Firmware/), [VRSleepDisableADB](https://github.com/MoonCherryFox/VRSleepDisableADB) |

### 10.2. Ж1–Ж10 и П1–П7 для обычной Pico 4

| # | Статус | Основание |
|---|---|---|
| Ж1 | **Да** | Автономная, 4 камеры трекинга, 6DoF, 2 контроллера в комплекте ([iprofishop](https://iprofishop.ru/catalog/igrovye_pristavki/pico_vr/88818/), [Wikipedia](https://en.wikipedia.org/wiki/PICO_4)) |
| Ж2 | **Да** (оговорка) | Godot на Pico 4 собирается и работает; вендорские расширения нужны только для passthrough ([форум](https://forum.godotengine.org/t/no-passthrough-option-on-pico-4-using-openxr-vendor-plugin-godot-v4-4-1-stable/108379)). Ранний PR 2022 года описывал только частичную поддержку и баги драйвера Vulkan на тогдашней прошивке — на нынешней не перепроверено ([PR #68023](https://github.com/godotengine/godot/pull/68023/)) |
| Ж3 | **Неизвестно** | Первичная настройка требует Wi-Fi и аккаунта Pico ([Pico](https://www.picoxr.com/global/blog/pico-4-setup)); работает ли потом неделями без интернета и не просит ли вход — источников нет. Проверка прав на приложения: «entitlement check» Pico убивает приложение без интернета через минуту, но он относится к приложениям, использующим Pico Platform SDK ([ALVR #1777](https://github.com/alvr-org/ALVR/issues/1777)); наш APK его не вызывает (предположение) |
| Ж4 | **Частично** | Всё интернет-зависимое (аккаунт, обновление) — дома. Прошивка офлайн: папка `dload` и «Offline Update», без понижения и без смены региона ([pico4.wiki](https://pico4.wiki/guides/ota/)). Режим разработчика локальный: Настройки → Общие → нажимать «Версия ПО» → Developer → USB-отладка; нужен ли при этом интернет — в источниках не указано; число нажатий в источниках расходится (7–10) ([ArborXR](https://help.arborxr.com/en/articles/10771596-developer-mode-usb-debugging-on-pico-4-ultra-enterprise), [Matts Digital](https://knowledge.matts-digital.com/en/virtual-reality/pico/pico-4-ultra-enterprise/how-to-enable-usb-debugging-on-the-pico-4-ultra-enterprise/)). Эти источники про Enterprise/Ultra, не про обычную Pico 4 |
| Ж5 | **Неизвестно** | Источник про Wi-Fi без интернета для Pico 4 не найден. Известен случай «No Network — Login authentication required» у пользователя, лечился сменой защиты роутера на WPA2-AES ([AVForums](https://www.avforums.com/threads/new-pico-4-user-wi-fi-cant-connect.2431810/)). Предположение: Android 10 остаётся в сети без интернета; ENet/UDP проверить |
| Ж6 | **Да** | Режим разработчика, «Установка неизвестных приложений», adb install ([anexplorer](https://anexplorer.io/device/vr-headset/pico-xr)); для Ultra Enterprise подтверждено отдельно ([Matts Digital](https://knowledge.matts-digital.com/en/virtual-reality/pico/pico-4-ultra-enterprise/how-to-install-an-app-on-the-pico-4-ultra-enterprise/)) |
| Ж7 | **Неизвестно** | Сохранение контура после сна/перезагрузки/замены очков на обычной Pico 4 источниками не подтверждено. Контур в очках привязан к конкретным очкам, не к стойке (предположение: при замене надо повторять быстрый круглый сидячий контур). Что у Enterprise есть отключение границы и «стационарная граница» ([ArborXR](https://help.arborxr.com/en/articles/6630022-configure-pico-system-settings)), у обычной — не подтверждено; у Neo 3 граница отключается в Developer ([VR Expert](https://knowledge.vr-expert.com/kb/how-to-turn-off-the-play-boundary-on-the-pico-neo-3/)) |
| Ж8 | **Нет штатно / обход не подтверждён** | Автозапуск по загрузке для сторонних приложений блокируется системой (`FEAT_PROCESS_INTERCEPT`), киоска и Device Manager нет ([pico-webxr-kiosk](https://github.com/robinhuse/pico-webxr-kiosk)). Остаётся замена лаунчера и «не давать очкам спать» — см. 10.4 |
| Ж9 | **Вероятно да** | XR2 Gen 1 такой же класс, как у Quest 2; на форуме Godot 90 кадров/с на Pico 4 в XR-шаблоне (июль 2024) ([форум](https://forum.godotengine.org/t/performance-considerations-for-stand-alone-xr/52324)). Свою сцену со светящимися материалами — замерить; 72 и 90 Гц заявлены в магазинах ([formula-iq](https://formula-iq.com/product-page/pico-4-256gb/)) |
| Ж10 | **Частично / неизвестно** | В РФ продаётся, но 14 одинаковых Global сразу — не подтверждено (10.1) |
| П1 | **Не выполняется, близко** | 36–65 тыс. ₽ за штуку против 20–25 тыс. ₽; в 2–4 раза дешевле Ultra Enterprise |
| П2 | **Ориентировочно** | 5300 мА·ч, зарядка 20 Вт, «2–3 часа» по описаниям магазинов, около 2 ч (в брифе) ([formula-iq](https://formula-iq.com/product-page/pico-4-256gb/), [virtualnyeochki](https://virtualnyeochki.ru/avtonomnyie-vr-ochki/avtonomnye-vr-ochki-pico/pico-neo-4-256-gb)). Игра с зарядкой — не проверено |
| П3 | **Неизвестно / риск** | Трекинг теряется в темноте и от ИК ([Reddit](https://www.reddit.com/r/PicoXR/comments/11q9jj5/new_pico_4_wont_track_anymore_limited_terrain/)); у Pico 4 нет дополнительных камер Ultra |
| П4 | **Да, через плагин** | Passthrough в Godot на Pico 4 — плагин OpenXR Vendors ≥ 4.0.0-rc1 ([форум](https://forum.godotengine.org/t/no-passthrough-option-on-pico-4-using-openxr-vendor-plugin-godot-v4-4-1-stable/108379)) |
| П5 | **Риск** | Модель 2022 года, преемник — Ultra; срок поддержки не публикуется (см. 10.1) |
| П6 | **Неизвестно** | Встроенные динамики, громкость в шумной локации не измерена; предположение: наушники |
| П7 | **Да** | 2×AA в контроллере ([iprofishop](https://iprofishop.ru/catalog/igrovye_pristavki/pico_vr/88818/)); время работы — неизвестно |

### 10.3. Цена

| | Количество | Цена за штуку | Итог |
|---|---|---|---|
| Прототип | 2 | 36–65 тыс. ₽ (реалистично 40–55 тыс.) | 72–130 тыс. ₽ (реалистично 80–110) |
| Парк | 14 (10 + 4 запас) | то же | 504–910 тыс. ₽ (реалистично 560–770) |

Цены — по страницам магазинов на 2026-10-01 с разбросом более чем в 1,5 раза; цену на 14 шт. узнавать у поставщика, снижает цену
только покупка опта и версия Global.

### 10.4. Ж8 на обычной Pico 4: основной способ и запасной

Что известно:
- Автозапуск по загрузке (BOOT_COMPLETED у стороннего приложения) на обычной Pico 4 системой блокируется ([pico-webxr-kiosk](https://github.com/robinhuse/pico-webxr-kiosk)) — свой receiver не поможет.
- PicoKiosk (замена лаунчера, GPL-3.0) заявляет: тестировался на Pico 4, white-list приложений, блокирует Home и шторку, опция «start on boot»; готовых APK нет, нужна сборка в Android Studio; прошивка, на которой тестировался, не названа; **поведение после сна и перезагрузки в описании не раскрыто** ([PicoKiosk](https://github.com/it03lab-ops/PicoKiosk)). Назначается через `adb shell pm set-home-activity <пакет>/.MainActivity`. База — PicoZen, репозиторий в архиве с августа 2025 ([PicoZen](https://github.com/barnabwhy/PicoZen)).
- Скрипт `pico4-adb-debloat` отключает системные пакеты через `pm disable-user` (и включает обратно `pm enable`), без root; сохраняет конфигурацию в файл и применяет к другим очкам; заявлен «для стоковой прошивки Pico 4», версии не названы ([pico4-adb-debloat](https://github.com/it03lab-ops/pico4-adb-debloat)).
- Официальный киоск Pico: на Neo 2/G2 — свойство `persist.pxr.force.home <пакет>,<активность>` ([Pico Kiosk Mode](https://static.appstore.picovr.com/docs/KioskMode/chapter_two.html)); на Neo 3 — Developer → Industry settings → Launcher App ([chapter 3](http://static.appstore.picovr.com/docs/KioskMode/chapter_three.html)). Для Pico 4 — **не подтверждено**.
- Сон: по умолчанию очки засыпают, когда их сняли (датчик на ремне), и просыпаются при надевании; затем глубокий сон ([руководство Pico](https://pico-web-tob.oss-cn-beijing.aliyuncs.com/20230825/document/1695015503416348672.pdf), цитата через поисковый ответ, сам PDF не прочитан). Что показывается после пробуждения — наше приложение или меню — **неизвестно**.
- Не давать засыпать: SDK Pico — `setprop persist.psensor.sleep.delay -1` (системный сон) и `persist.psensor.screenoff.delay 65535` (экран) ([Pico SDK ADB](https://sdk.picovr.com/docs/ADBCommand/chapter_two.html)), версии прошивок не указаны. Для Pico 4 в той же логике — скрытые экраны настроек Android и приложение Pico-4/Settings ([VRSleepDisableADB](https://github.com/MoonCherryFox/VRSleepDisableADB), [Pico-4/Settings](https://github.com/Pico-4/Settings)); репозиторий VRSleepDisableADB — вторичный и не вызывает доверия, считать гипотезой. Свойство `pvr.factorytest.never.sleep` обнуляется при каждой загрузке и меняется модулем, который требует root и LSPosed — нам не подходит ([PicoNeverSleep](https://github.com/chaixshot/PicoNeverSleep)). Цикл `adb shell input keyevent 224` раз в 30 с сообщается рабочим на Ultra, на Pico 4 — неизвестно, требует подключённого adb.

**Порядок (основной).** Не бороться с Pico, а убрать причины ухода из приложения:
1. Сон: проверить в Настройках, есть ли «Никогда»; если нет — `setprop persist.psensor.sleep.delay -1`, `persist.psensor.screenoff.delay 65535`; помнить, что `persist.*` по документации переживает перезагрузку (предположение для Pico 4). Если сон отключить удалось, очки не засыпают, пока надеты на стойку или заряжаются, и возврат после сна не нужен — остаётся только перезагрузка.
2. Лаунчер: собрать PicoKiosk, поставить, `pm set-home-activity`, в белом списке только наш APK. Проверка: Home и перезагрузка возвращают в приложение. Пробовать на одних очках; сначала без `pm disable-user` стокового лаунчера (его отключение может оставить очки без рабочего Home; при потере доступа вернуть через `adb shell pm enable`). Параллельно проверить `persist.pxr.force.home` как запасной системный механизм.
3. Если приложение закрылось само — стойка запускает его командой с мини-ПК по Wi-Fi adb (`adb connect` + `am start`); Wi-Fi adb после перезагрузки очков по умолчанию выключается (стандарт Android 10), поэтому — только идея для проверки, **предположение**.

**Запасной вариант (если 1–3 не прошли).** Помощник у стойки (мастер/организатор): перед сменой включить очки, выбрать приложение «Библиотека → Наше приложение» вручную, затем отдать игроку; очки после снятия считать «занятыми» до возврата помощнику. Цена вопроса — 10–20 с на смену и человек на каждой стойке; приложение должно само восстанавливать сессию на сервере по ключу игрока (это общая защита от сна и сбоя сети, и она нужна в любом случае).

### 10.5. Сидячий контур и замена очков (Ж7)

Что известно: у Enterprise при первом включении выбирается быстрый круговой контур (сидя/стоя) или собственный ([VR Expert](https://knowledge.vr-expert.com/kb/how-to-set-up-a-boundary-on-the-pico-4-enterprise/)); у Neo 3 границу можно отключить в Developer. Про Pico 4 (обычную) — подтверждений нет. Решения по убыванию надёжности: (1) играть сидя без сохранения мира и без привязки к стойке — в Godot использовать `local` reference space и пересчитывать позицию игрока в рывке начала забега, т.е. от контура не зависеть (предположение, зависит от клиента); (2) запретить границу в Developer, если пункт есть (на Pico 4 не подтверждён); (3) один быстрый сидячий круг в начале каждой сессии помощником. Проверка — п. 7 чек-листа, пункт 3.

### 10.6. Godot на Pico 4 (Ж9)

- Renderer: на Pico 4 работали и Mobile (Vulkan), и Compatibility; ранняя поддержка (2022) страдала от ошибок Vulkan-драйвера на тогдашней прошивке ([PR #68023](https://github.com/godotengine/godot/pull/68023/)). Форум Godot: март 2024 советовали Compatibility для автономных очков; в феврале 2026 (Godot 4.6) Mobile в тестах быстрее Compatibility на Quest 3 и признан реальным вариантом ([форум](https://forum.godotengine.org/t/performance-considerations-for-stand-alone-xr/52324)) — на Pico 4 сравнительных замеров не найдено. Решение — п. 7, пункт 6.
- Частота: 72 и 90 Гц заявлены (Pico 4), стабильность на нашей сцене — неизвестно.
- Фовеация (4.6+/4.7) на Pico 4 — не проверялась; ошибки в Godot на Quest описаны в #112988 и #112834.

### 10.7. Порядок подготовки парка для обычной Pico 4

**Дома, с интернетом (каждое устройство):**
1. Купить Global; перед включением записать серийный номер и партию. Включить, язык, Wi-Fi, вход в аккаунт Pico (создаётся приложением Pico на телефоне; один общий аккаунт или по аккаунту на очки — решение владельца, для проверки Ж3 достаточно одного).
2. Обновить прошивку: самую новую получить на первых очках через Settings → General → System Update, остальные — до неё же (офлайн из `dload`, файл брать из источника, не распаковывая). Не смешивать Global и CN, не понижать.
3. Режим разработчика, USB-отладка, «Установка неизвестных приложений».
4. На ПК: adb, Android Studio (для сборки PicoKiosk), шаблоны Godot 4.7.2 — всё заранее.
5. Поставить PicoKiosk, назначить лаунчер, настроить отключение сна (10.4); применить скрипт `pm disable-user` — только на одних очках и после проверки, остальным — по сохранённой конфигурации.
6. **Отключить обновления:** документированного способа для обычной Pico 4 нет. Рабочий вариант — после подготовки забыть домашнюю Wi-Fi-сеть на очках и держать их только в сети площадки без интернета; тогда обновлению неоткуда прийти (предположение, проверить).

**На площадке, офлайн:** подключить к UniFi, `adb install -r` нашего APK по USB-C, настроить контур, проверить возврат из сна и перезагрузки. Запись «Ж3-ночь»: оставить включённой на 3 дня.

### 10.8. Обновлённая закупка (обычная Pico 4)

| Позиция | Прототип | Парк | Цена | Заметки |
|---|---|---|---|---|
| Pico 4 Global, 8/128 или 8/256 | 2 | 14 | 36–65 тыс. ₽ (10.3) | одна партия, не CN |
| NiMH AA, комплекты | 8 + 8 запас | 112 | неизвестно | по 2×AA на контроллер, 2 комплекта на пару |
| Зарядное для AA | 2 | 6 | неизвестно | |
| Зарядные блоки и кабели USB-C (до 20 Вт, 5300 мА·ч) | 2 | 14 + 2 | неизвестно | брать комплектные |
| Кабель USB-C для adb (данные) | 2 | 3 | неизвестно | |
| Внешний аккумулятор/ремень | 1 по желанию | по необходимости | неизвестно | совместимость с Pico 4 не проверена |
| Сменные накладки (комплектные + запас) | 2 | 14 | неизвестно | |
| Проставки для очков | 2 | по потребности | неизвестно | не исследованы |
| Дополнительно: ПК для сборки APK/PicoKiosk | 1 | 1 | — | Android Studio, Windows для adb-debloat |
| Device Manager / Business Suite | — | — | — | не нужны (только Enterprise) |

### 10.9. Дополнительные источники раздела 10

- PicoKiosk: <https://github.com/it03lab-ops/PicoKiosk>, <https://github.com/it03lab-ops/pico4-adb-debloat>, <https://github.com/barnabwhy/PicoZen>
- Отказ автозапуска у обычной Pico: <https://github.com/robinhuse/pico-webxr-kiosk>
- Киоск Pico (Neo): <https://static.appstore.picovr.com/docs/KioskMode/chapter_two.html>, <http://static.appstore.picovr.com/docs/KioskMode/chapter_three.html>
- Сон: <https://sdk.picovr.com/docs/ADBCommand/chapter_two.html>, <https://github.com/MoonCherryFox/VRSleepDisableADB>, <https://github.com/chaixshot/PicoNeverSleep>, <https://github.com/Pico-4/Settings>
- CN/Global: <https://vr180g.com/pico/picochina.php?l=en>, <https://owomushi.com/Pico-Firmware/>, <https://pico4.wiki/guides/ota/>
- Entitlement check: <https://github.com/alvr-org/ALVR/issues/1777>
- Godot: <https://forum.godotengine.org/t/performance-considerations-for-stand-alone-xr/52324>, <https://github.com/godotengine/godot/pull/68023/>
- Цены: <https://iprofishop.ru/catalog/igrovye_pristavki/pico_vr/88818/>, <https://offo.ru/catalog/shlem-virtualnoy-realnosti/shlem-vr-pico-4-4320x2160-128-gb-90-gts-bazovaya-global/>, <https://tech-iq.ru/product/avtonomnyj-vr-shlem-pico-4-128-gb/>, <https://portal-shop.com/catalog/vr_ochki/vr_shlemy/2277/>, <https://vr-zone.ru/avtonomnyy-vr-shlem-pico-4-256-gb/>, <https://formula-iq.com/product-page/pico-4-256gb/>, <https://virtualnyeochki.ru/avtonomnyie-vr-ochki/avtonomnye-vr-ochki-pico/pico-neo-4-256-gb>
