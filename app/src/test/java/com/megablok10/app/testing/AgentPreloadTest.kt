package com.megablok10.app.testing

import java.lang.management.ManagementFactory
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Тестовая JVM стартует с Java-агентом ByteBuddy (-javaagent, app/build.gradle.kts): Paparazzi берёт уже загруженный агент и не
 * подключается к своей JVM на лету — на macOS под нагрузкой это подключение падало по таймауту и роняло скриншот-тесты.
 */
class AgentPreloadTest {
    @Test fun byteBuddyAgentIsLoadedAtJvmStart() {
        val args = ManagementFactory.getRuntimeMXBean().inputArguments
        assertTrue("тестовая JVM без -javaagent:byte-buddy-agent: $args", args.any { it.startsWith("-javaagent:") && "byte-buddy-agent" in it })
        // Тот же поиск, что делает ByteBuddyAgent.install(): класс-установщик в системном загрузчике и его Instrumentation.
        val installer = Class.forName("net.bytebuddy.agent.Installer", true, ClassLoader.getSystemClassLoader())
        assertNotNull(installer.getMethod("getInstrumentation").invoke(null))
    }
}
