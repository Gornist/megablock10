import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

// Мост «Сеть»: хранилище документов в памяти и SQLite, дальше API по WebSocket, правила и операции с ценностями
// (docs/netrun-tasks.md, B0–B3). Работает на мини-ПК площадки, не на телефоне, поэтому Animal Sniffer не нужен.
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("io.gitlab.arturbosch.detekt")
    application
}

application { mainClass.set("com.megablok10.netrun.bridge.MainKt") }

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

    // WebSocket-сервер: Java-WebSocket — один небольшой JAR на чистой Java (без Netty/Ktor-рантайма), сервер и клиент по RFC 6455.
    implementation("org.java-websocket:Java-WebSocket:1.5.7")
    // Java-WebSocket пишет через slf4j; своё логирование Мост ведёт сам, поэтому привязка «в никуда».
    runtimeOnly("org.slf4j:slf4j-nop:2.0.13")

    testImplementation("junit:junit:4.13.2")
}
