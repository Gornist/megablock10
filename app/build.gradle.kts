plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.devtools.ksp")
    id("app.cash.paparazzi")
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
    }

    buildFeatures {
        compose = true
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
}
