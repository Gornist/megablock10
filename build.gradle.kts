plugins {
    id("com.android.application") version "8.5.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("org.jetbrains.kotlin.jvm") version "1.9.24" apply false   // :kit — чистый Kotlin/JVM, та же версия Kotlin, что у :app
    id("com.google.devtools.ksp") version "1.9.24-1.0.20" apply false
    id("io.gitlab.arturbosch.detekt") version "1.23.7" apply false   // статический анализ Kotlin: сложность, мёртвый приватный код, «запахи»
    id("app.cash.paparazzi") version "1.3.4" apply false   // скриншот-тесты Compose на JVM, без эмулятора
    id("ru.vyarus.animalsniffer") version "2.0.1" apply false   // :kit — вызовы только тех API, что есть на Android 8.0 (minSdk 26)
}
