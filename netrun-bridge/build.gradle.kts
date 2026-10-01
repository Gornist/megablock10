import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Мост «Сеть»: хранилище документов в памяти и SQLite, дальше API по WebSocket, правила и операции с ценностями
// (docs/netrun-tasks.md, B0–B3). Работает на мини-ПК площадки, не на телефоне, поэтому Animal Sniffer не нужен.
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("io.gitlab.arturbosch.detekt")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
tasks.withType<KotlinCompile>().configureEach {
    compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
}

detekt {
    buildUponDefaultConfig = true
    config.setFrom(file("../config/detekt/detekt.yml"))
    parallel = true
}

dependencies {
    api(project(":kit"))
    // JsonObject — тип поля data документа; плагин сериализации не нужен, только разбор и сборка дерева JSON.
    api("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    // SQLite через JDBC: драйвер несёт нативную библиотеку для Linux/macOS/Windows.
    implementation("org.xerial:sqlite-jdbc:3.46.1.3")

    testImplementation("junit:junit:4.13.2")
}
