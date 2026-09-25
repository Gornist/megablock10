package com.megablok10.app.screenshots

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM скриншот-тестов стартует с Java-агентом ByteBuddy (-javaagent, app/build.gradle.kts): Paparazzi берёт уже загруженный агент и не
 * подключается к своей JVM на лету — на macOS под нагрузкой это подключение падало по таймауту и роняло скриншот-тесты.
 * Лежит в screenshots/, потому что агент подключается только к JVM скриншотов (testDebugUnitTest), а не к остальным тестам.
 */
class AgentPreloadTest {
    @Test fun byteBuddyAgentIsLoadedAtJvmStart() {
        // java.lang.management нет в android.jar, против которого компилируются тесты модуля, — только в самой тестовой JVM.
        val runtime = Class.forName("java.lang.management.ManagementFactory").getMethod("getRuntimeMXBean").invoke(null)
        @Suppress("UNCHECKED_CAST")
        val args = Class.forName("java.lang.management.RuntimeMXBean").getMethod("getInputArguments").invoke(runtime) as List<String>
        assertTrue("тестовая JVM без -javaagent:byte-buddy-agent: $args", args.any { it.startsWith("-javaagent:") && "byte-buddy-agent" in it })
        // Тот же поиск, что делает ByteBuddyAgent.install(): класс-установщик в системном загрузчике и его Instrumentation.
        val installer = Class.forName("net.bytebuddy.agent.Installer", true, ClassLoader.getSystemClassLoader())
        assertNotNull(installer.getMethod("getInstrumentation").invoke(null))
    }
}
