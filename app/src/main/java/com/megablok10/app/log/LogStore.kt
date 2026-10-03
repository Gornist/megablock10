package com.megablok10.app.log

import android.content.Context
import java.io.File

/** Журнал приложения глазами Настроек: размер, очистка, сброс на диск, архив. Сам журнал — [Mb10Log]. */
interface LogStore {
    fun sizeBytes(): Long
    fun clear()
    fun flush()
    fun exportZip(deviceInfo: String): File?
}

class Mb10LogStore(private val context: Context) : LogStore {
    override fun sizeBytes(): Long = Mb10Log.sizeBytes()
    override fun clear() = Mb10Log.clear()
    override fun flush() = Mb10Log.flush()
    override fun exportZip(deviceInfo: String): File? = Mb10Log.exportZip(context, deviceInfo)
}
