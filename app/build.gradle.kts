import java.util.Properties
import java.util.concurrent.Callable

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
    id("app.cash.paparazzi")
    id("io.gitlab.arturbosch.detekt")
}

// Настройки конкретной игры задаются при сборке, а не в публичном коде: адрес сервера мастера и режим первого запуска.
// Источники по порядку: свойство Gradle (-Pmb10.collectorUrl=…), переменная окружения MB10_COLLECTOR_URL, local.properties (в .gitignore).
fun buildSetting(prop: String, env: String, default: String): String {
    providers.gradleProperty(prop).orNull?.let { return it }
    System.getenv(env)?.takeIf { it.isNotBlank() }?.let { return it }
    val local = rootProject.file("local.properties")
    if (local.exists()) {
        val props = Properties()
        local.inputStream().use { props.load(it) }
        props.getProperty(prop)?.let { return it }
    }
    return default
}
val collectorUrl = buildSetting("mb10.collectorUrl", "MB10_COLLECTOR_URL", "")
val allowManualSetup = buildSetting("mb10.allowManualSetup", "MB10_ALLOW_MANUAL_SETUP", "false")

detekt {
    buildUponDefaultConfig = true
    config.setFrom(rootProject.file("config/detekt/detekt.yml"))
    baseline = file("detekt-baseline.xml")     // старые находки заморожены, новые ломают проверку; обновить: ./gradlew :app:detektBaseline
    source.setFrom("src/main/java", "src/debug/java", "src/test/java")
    parallel = true
}

android {
    namespace = "com.megablok10.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.megablok10.app"
        // minSdk 26 — покрывает подавляющее большинство реальных телефонов игроков,
        // при этом даёт нормальную поддержку EC-криптографии из коробки.
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1-mvp"
        // Адрес сервера мастера по умолчанию (пусто — не задан: отправка выключена, пока адрес не придёт по QR персонажа или не введён в Настройках).
        buildConfigField("String", "DEFAULT_COLLECTOR_URL", "\"${collectorUrl.trim().trimEnd('/')}\"")
        // Ручное создание персонажа на первом запуске. Выключено везде, включая debug-APK из CI, который и раздаётся игрокам: персонажа выдаёт мастер QR-кодом.
        // Разработчику без мастера: mb10.allowManualSetup=true в local.properties (стенд e2e создаёт персонажей отладочными командами и этого не требует).
        buildConfigField("boolean", "ALLOW_MANUAL_SETUP", allowManualSetup.toBoolean().toString())
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
        // Отчёты компилятора Compose (какие функции перерисовываются лишний раз): ./gradlew :app:compileDebugKotlin -Pmb10.composeReports=true --rerun-tasks
        // → app/build/compose_reports/. Подробности в README (раздел про проверки).
        if (providers.gradleProperty("mb10.composeReports").orNull == "true") {
            val out = layout.buildDirectory.dir("compose_reports").get().asFile.absolutePath
            freeCompilerArgs += listOf(
                "-P", "plugin:androidx.compose.compiler.plugins.kotlin:reportsDestination=$out",
                "-P", "plugin:androidx.compose.compiler.plugins.kotlin:metricsDestination=$out"
            )
        }
    }
    packaging {
        resources.excludes.add("META-INF/*")
    }
    // Robolectric (тесты на настоящей Room в памяти, см. testing/RoomTest.kt) берёт манифест и ресурсы из сборки.
    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
    // Android Lint — полный набор проверок по умолчанию (не только уровень API — NewApi поймал реальное падение,
    // PrintWriter(OutputStream, Boolean, Charset) есть только с API 33, а minSdk — 26). Модуль kit сторожит свою
    // границу отдельно (Animal Sniffer, сигнатура API 26). Старые находки заморожены в lint-baseline.xml, как у
    // detekt — новые ломают проверку. Обновить: ./gradlew :app:updateLintBaseline. Запуск: ./gradlew :app:lintDebug
    // (CI и scripts/check.sh).
    lint {
        disable += setOf(
            // Синхронная запись (commit, не apply) здесь всегда намеренная — после неё сразу уходит подтверждение
            // (серверу, другому телефону) или подписываются записи для мастера тем же ключом; см. правило в
            // docs/architecture.md, «Хранилища». Предложение lint (заменить на фоновый apply) прямо противоречит ему.
            "ApplySharedPref",
            // Сеть площадки офлайн целиком (docs/network-spec.md, «Интернета в сети нет и не будет») — TLS в LAN без
            // интернета для чата/NSD не имеет смысла (HTTPS у коллектора — отдельная история, уже поверх этого).
            "InsecureBaseConfiguration",
            // Портретная ориентация — намеренный выбор телефонного интерфейса игрока, не упущение.
            "LockedOrientationActivity", "DiscouragedApi",
            // DebugQrReceiver обязан быть exported без разрешения — им управляет `adb shell am broadcast` снаружи
            // приложения (стенд e2e, scripts/e2e/lib.sh); он есть только в debug-сборке, игрокам не попадает.
            "ExportedReceiver",
            // Версии зависимостей обновляются отдельным осознанным решением, не через находку линтера в CI.
            "GradleDependency",
        )
        baseline = file("lint-baseline.xml")
        abortOnError = true
        textReport = true
        textOutput = file("stdout")   // находки — прямо в журнал сборки, без скачивания отчёта
    }
}

// Java-агент ByteBuddy (им пользуется Paparazzi) — загружается при старте тестовой JVM, а не подключается на лету. Версия — та же,
// что приходит с Paparazzi 1.3.4; при расхождении не страшно: ByteBuddy ищет загруженный агент по имени класса в системном загрузчике.
val byteBuddyAgent: Configuration by configurations.creating { isTransitive = false }
dependencies { byteBuddyAgent("net.bytebuddy:byte-buddy-agent:1.14.16") }

// Скриншот-тесты (Paparazzi: layoutlib со своей Skia) и остальные unit-тесты (Robolectric: android-all, нативный SQLite) — в разных
// JVM. В одной JVM нативные библиотеки конфликтовали: на macOS скриншоты после Robolectric падали SIGSEGV в layoutlib (25.09).
// Paparazzi привязан к test<Variant>UnitTest (его verify/record зовут именно её) — ей оставлены только скриншоты; остальное идёт
// в test<Variant>UnitTestNoScreenshots, от которой она зависит. Итог прежний: testDebugUnitTest и verifyPaparazziDebug гоняют ВСЕ
// тесты приложения, каждый ровно один раз (задача без скриншотов от режима Paparazzi не зависит и во втором вызове up-to-date).
// Один тест: ./gradlew :app:testDebugUnitTestNoScreenshots --tests '*RoomTest*' (скриншот — verifyPaparazziDebug --tests …).
val screenshotTests = "com.megablok10.app.screenshots.*"
for (variant in listOf("Debug", "Release")) {
    val unitTest = "test${variant}UnitTest"
    val noScreenshots = tasks.register<Test>("${unitTest}NoScreenshots") {
        description = "Unit-тесты варианта ${variant.lowercase()} без скриншот-тестов — в своей JVM, без Paparazzi"
        group = "verification"
        // Классы и classpath — те же, что у задачи AGP (её создают после вычисления скрипта, поэтому лениво). Через Callable, а не
        // provider задачи: provider нёс бы зависимость от самой test<Variant>UnitTest, а она зависит от этой — цикл.
        val base = tasks.named<Test>(unitTest)
        testClassesDirs = files(Callable { base.get().testClassesDirs })
        classpath = files(Callable { base.get().classpath })
        filter.excludeTestsMatching(screenshotTests)
        // log/LogContractTest читает стенд e2e и исходники как текст: без этих входов правка скрипта оставляла бы задачу up-to-date.
        inputs.files(
            rootProject.fileTree("scripts/e2e") { include("**/*.sh", "log-contract.tsv") },
            fileTree("src/main/java"), fileTree("src/debug/java"), rootProject.fileTree("kit/src/main/kotlin"),
        ).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("logContractFiles")
    }
    tasks.withType<Test>().matching { it.name == unitTest }.configureEach {
        dependsOn(noScreenshots)
        filter.includeTestsMatching(screenshotTests)
        // Paparazzi зовёт ByteBuddyAgent.install(). Подключение на лету (attach) на macOS под нагрузкой ненадёжно: сначала падал внешний
        // процесс-подключатель («Could not self-attach … using external process»), с -Djdk.attach.allowAttachSelf — таймаут сокета
        // собственного Attach Listener («.java_pid… doesn't respond within 10500ms»). Агент, загруженный через -javaagent, install()
        // находит сразу: ни внешнего процесса, ни сигнала SIGQUIT, ни сокета (проверено strace: 0/0/0 против 1/2/2 при attach).
        // Разделение JVM этого не касается (attach нужен Paparazzi в любой JVM) — агент остаётся. Стережёт screenshots/AgentPreloadTest.
        val agentJar = byteBuddyAgent
        jvmArgumentProviders.add(CommandLineArgumentProvider { listOf("-javaagent:${agentJar.singleFile.absolutePath}") })
        // Запасной путь, если агент при старте почему-то не найдётся: подключение изнутри JVM, без внешнего процесса.
        jvmArgs("-Djdk.attach.allowAttachSelf=true")
    }
}

tasks.withType<Test>().configureEach {
    // Robolectric (android-all) и Paparazzi (layoutlib) — тяжёлые; по умолчанию Gradle даёт тестовой JVM 512 МБ.
    maxHeapSize = "2g"
    // Упавший тест — с полным текстом исключения прямо в журнале: отчёты CI отсюда не скачать, а по классу исключения причину не понять.
    testLogging { exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }

    // Итог прогона одной строкой в журнале (CI не показывает, сколько тестов на самом деле выполнилось).
    afterSuite(KotlinClosure2<TestDescriptor, TestResult, Unit>({ suite, result ->
        if (suite.parent == null) println("$name: тестов ${result.testCount}, прошло ${result.successfulTestCount}, упало ${result.failedTestCount}, пропущено ${result.skippedTestCount}")
    }))
}

ksp {
    // Схемы Room экспортируются в app/schemas и коммитятся: по ним пишутся и проверяются миграции.
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    // Переиспользуемое ядро (kit/README.md): журнал, подписи, шифрование, сеть на площадке, передачи, синхронизация с сервером.
    implementation(project(":kit"))

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    // Экраны — через ViewModel (переживают поворот и смену вкладки): viewModel() и collectAsStateWithLifecycle в Compose.
    // 2.6.x — та же линия lifecycle, что уже приходит с activity-compose 1.9 и Compose BOM 2024.06.
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.6.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.2")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.6.2")

    // QR: генерация своего кода и сканирование чужого
    implementation("com.google.zxing:core:3.5.3")
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")

    // Локальное хранилище: Character/Container/Transaction вместо SharedPreferences
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // Голосовые звонки: чистый P2P поверх LAN, без STUN/TURN — ICE соберёт
    // host-кандидаты напрямую. org.webrtc:google-webrtc официально мёртв
    // (Google больше не публикует precompiled Android-сборки), этот форк —
    // активно поддерживаемая замена с тем же пакетом org.webrtc.*.
    implementation("io.github.webrtc-sdk:android:144.7559.09")

    // Связь с мастерским коллектором (admin-web) — обычный HTTP на ноутбуке
    // мастера в той же локальной сети, не P2P. См. CollectorClient.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
    // Настоящий SQLite на JVM — чтобы прогонять миграции Room на базе с данными (MigrationDataTest)
    testImplementation("org.xerial:sqlite-jdbc:3.46.1.0")
    // Настоящая Room в памяти на JVM: транзакции, откаты, выдача seq — то, что фейками не проверить (testing/RoomTest.kt)
    testImplementation("org.robolectric:robolectric:4.13")
}
