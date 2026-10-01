pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "megablok10-app"
include(":app")
// Переиспользуемое ядро без Android и без игровой логики (kit/README.md): сеть на площадке, подписи, передачи, синхронизация.
include(":kit")
// Мост «Сеть» (docs/netrun-bridge-protocol.md): документы и хранилище на мини-ПК площадки. Чистая JVM, зависит от :kit.
include(":netrun-bridge")
// Общие правила игры без Android (rules/README.md): тиры, эффекты демонов, кодек предмета, решение о сигнале СБ.
include(":rules")
