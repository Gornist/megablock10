plugins {
    // AGP 9.2: нужен Gradle 9.4.1+, compileSdk до 37; Kotlin встроен в AGP (плагин kotlin.android не подключается — версия KGP
    // берётся из kotlin.plugin.compose / kotlin.jvm ниже). Compose 1.12 требует 9.1+, lifecycle 2.11 — 9.2.
    id("com.android.application") version "9.2.1" apply false
    // Компилятор Compose с Kotlin 2.0 — плагин Kotlin той же версии (вместо composeOptions.kotlinCompilerExtensionVersion).
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21" apply false
    id("org.jetbrains.kotlin.jvm") version "2.4.21" apply false   // :kit — чистый Kotlin/JVM, та же версия Kotlin, что у :app
    id("com.google.devtools.ksp") version "2.3.12" apply false   // KSP2: версия больше не привязана к версии Kotlin
    id("dev.detekt") version "2.0.0-alpha.6" apply false   // статический анализ Kotlin: сложность, мёртвый приватный код, «запахи»; 2.0 — на Kotlin 2.4 (alpha.6: 2.4.10), пина версии компилятора не нужно
    id("app.cash.paparazzi") version "2.0.0-alpha05.1" apply false   // скриншот-тесты Compose на JVM, без эмулятора; alpha05.1 собран под AGP 9; 1.3.5 (последняя стабильная) не знает compileSdk 36+
    id("ru.vyarus.animalsniffer") version "2.0.1" apply false   // :kit — вызовы только тех API, что есть на Android 8.0 (minSdk 26)
}
