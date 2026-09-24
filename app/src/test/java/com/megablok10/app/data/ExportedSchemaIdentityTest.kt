package com.megablok10.app.data

import com.megablok10.app.testing.RoomTest
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Закоммиченная схема текущей версии — та самая, что собирает Room: её отпечаток (identityHash) совпадает с тем, что Room пишет
 * в новую базу. Room перезаписывает app/schemas только при расхождении таблиц, поэтому схему, собранную или поправленную вручную,
 * ловит этот тест, а не шаг CI «Схема Room совпадает с закоммиченной».
 */
@RunWith(RobolectricTestRunner::class)
class ExportedSchemaIdentityTest : RoomTest() {
    @Test fun committedSchemaHasTheIdentityHashRoomUses() {
        val version = db.openHelper.readableDatabase.version
        val json = File("schemas/com.megablok10.app.data.Mb10Database/$version.json").readText()
        val exported = Regex("\"identityHash\":\\s*\"(\\w+)\"").find(json)!!.groupValues[1]
        val actual = db.openHelper.readableDatabase.query("SELECT identity_hash FROM room_master_table").use { it.moveToFirst(); it.getString(0) }
        assertEquals("app/schemas/…/$version.json не совпадает со схемой, которую собирает Room — пересоберите и закоммитьте", actual, exported)
    }
}
