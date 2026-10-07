package com.megablok10.app.voice

import java.io.File

/**
 * Файлы голосовых сообщений: `<dir>/<id>.m4a`. Звук лежит файлом, а не в Room: строка сообщения остаётся маленькой, а окно курсора Room (2 МБ)
 * не страдает от записей по 150 КБ. Запись атомарна (временный файл → переименование): подтверждение «доставлено» уходит только после неё.
 * Имя файла берётся только из проверенного id ([VoiceProtocol.isValidId]) — чужой id не может выйти из папки.
 */
class VoiceStore(private val dir: File) {
    fun file(id: String): File? = if (VoiceProtocol.isValidId(id)) File(dir, "$id.m4a") else null

    fun exists(id: String): Boolean = file(id)?.isFile == true

    /** true — файл сохранён (или такой же уже лежал: повторная доставка той же строки). */
    fun write(id: String, bytes: ByteArray): Boolean {
        val target = file(id) ?: return false
        if (bytes.isEmpty() || bytes.size > VoiceLimits.MAX_AUDIO_BYTES) return false
        if (target.isFile && target.length() == bytes.size.toLong()) return true
        dir.mkdirs()
        val temp = File(dir, "$id.tmp")
        return try {
            temp.writeBytes(bytes)
            temp.renameTo(target)
        } catch (e: java.io.IOException) {
            temp.delete()
            false
        }
    }

    /** Принять уже записанный рекордером файл под id. */
    fun adopt(id: String, source: File): Boolean = try { write(id, source.readBytes()) } catch (e: java.io.IOException) { false }

    fun read(id: String): ByteArray? = try { file(id)?.takeIf { it.isFile }?.readBytes() } catch (e: java.io.IOException) { null }

    fun delete(id: String) { file(id)?.delete() }

    /** Сброс персонажа: все записи стираются. */
    fun deleteAll() { dir.listFiles()?.forEach { it.delete() } }
}
