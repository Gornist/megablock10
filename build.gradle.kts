plugins {
    id("com.android.application") version "8.13.2" apply false   // последняя стабильная 8.x: AGP 9 требует альфа-версий Paparazzi и detekt
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    // Компилятор Compose с Kotlin 2.0 — плагин Kotlin той же версии (вместо composeOptions.kotlinCompilerExtensionVersion).
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.20" apply false
    id("org.jetbrains.kotlin.jvm") version "2.4.20" apply false   // :kit — чистый Kotlin/JVM, та же версия Kotlin, что у :app
    id("com.google.devtools.ksp") version "2.3.12" apply false   // KSP2: версия больше не привязана к версии Kotlin
    id("io.gitlab.arturbosch.detekt") version "1.23.8" apply false   // статический анализ Kotlin: сложность, мёртвый приватный код, «запахи»
    id("app.cash.paparazzi") version "2.0.0-alpha05" apply false   // скриншот-тесты Compose на JVM, без эмулятора; 1.3.5 (последняя стабильная) не знает compileSdk 36
    id("ru.vyarus.animalsniffer") version "2.0.1" apply false   // :kit — вызовы только тех API, что есть на Android 8.0 (minSdk 26)
}

// detekt 1.23.x собран с Kotlin 2.0.21 и сам проверяет, что его компилятор той же версии («detekt was compiled with
// Kotlin 2.0.21 but is currently running with …»). Проект компилируется Kotlin новее — detekt получает свою версию
// компилятора только в своей конфигурации, код приложения это не затрагивает.
subprojects {
    configurations.matching { it.name == "detekt" }.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") useVersion("2.0.21")
        }
    }
}
