import java.util.Properties

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
}

ksp {
    // Схемы Room экспортируются в app/schemas и коммитятся: по ним пишутся и проверяются миграции.
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")

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
}
