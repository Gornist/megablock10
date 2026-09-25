package com.megablok10.app.testing

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.SQLiteMode
import org.robolectric.config.ConfigurationRegistry

/**
 * Robolectric работает с SQLite в прежнем режиме (sqlite4java), а не в нативном: нативный грузит в тестовую JVM свою Skia, и на macOS
 * Paparazzi, идущий следом в той же JVM, падал SIGSEGV (app/build.gradle.kts, robolectric.sqliteMode).
 */
@RunWith(RobolectricTestRunner::class)
class SqliteModeTest {
    @Test fun robolectricUsesLegacySqlite() {
        assertEquals(SQLiteMode.Mode.LEGACY, ConfigurationRegistry.get(SQLiteMode.Mode::class.java))
    }
}
