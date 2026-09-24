import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Переиспользуемое ядро без Android и без знаний об игре (см. kit/README.md): чистый Kotlin/JVM, собирается и тестируется
// без эмулятора и без Android SDK. Приложение (:app) подключает его как обычную зависимость; другое приложение со схожей
// логикой (офлайн-сеть на площадке, подписанные передачи, мастерский сервер) — так же.
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("io.gitlab.arturbosch.detekt")
}

// Байткод 17 — как у :app (compileOptions/jvmTarget там же): модуль целиком уходит в APK через D8.
// Код модуля обязан обходиться API, которые есть на Android 8.0 (minSdk 26), — см. kit/README.md, раздел «Правила».
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
tasks.withType<KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
}

detekt {
    buildUponDefaultConfig = true
    // Путь от каталога модуля, а не от rootProject: модуль можно собрать и в чужой сборке (другое приложение, отдельный стенд).
    config.setFrom(file("../config/detekt/detekt.yml"))
    parallel = true
}

dependencies {
    // api: типы корутин (CoroutineScope, Flow) — часть публичных сигнатур модуля.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
