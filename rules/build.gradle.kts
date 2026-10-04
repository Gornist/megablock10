import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Общие правила игры без Android (rules/README.md): тиры, эффекты демонов, кодек предмета в карточке, решение о сигнале СБ.
// Чистый Kotlin/JVM: те же правила нужны приложению (:app) и, дальше, Мосту сети. Живёт отдельно от :kit, потому что kit —
// механика без знаний об игре, а здесь именно игра.
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("io.gitlab.arturbosch.detekt")
    id("ru.vyarus.animalsniffer")
}

// Байткод 17 — как у :app (compileOptions/jvmTarget там же): модуль целиком уходит в APK через D8.
// Код модуля обязан обходиться API, которые есть на Android 8.0 (minSdk 26), — это проверяет Animal Sniffer ниже.
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

// Модуль собирается JDK 17+, а работает на телефонах с Android 8.0: вызов API, которого там нет (например, конструктора
// PrintWriter с Charset — он есть только с Android 13), компилируется молча и падает NoSuchMethodError на телефоне игрока.
// Animal Sniffer сверяет байткод основного кода с сигнатурой API Android 26 и ломает сборку на таком вызове
// (задача animalsnifferMain, входит в check; CI и scripts/check.sh зовут её явно). Тесты идут на JVM — их не проверяем.
animalsniffer {
    sourceSets = listOf(project.sourceSets["main"])
}

dependencies {
    api(project(":kit"))
    signature("net.sf.androidscents.signature:android-api-level-26:8.0.0_r2@signature")

    testImplementation("junit:junit:4.13.2")
    // Тесты читают и выгружают JSON для GDScript-порта (netrun/data/rules/breach.json, netrun/tests/fixtures/breach_golden.json).
    // Только тестам: основной код модуля остаётся без JSON-библиотек (он уходит в APK).
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
}
