package com.megablok10.netrun.bridge.phone

import com.megablok10.kit.crypto.Ecdsa
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermissions
import java.security.PrivateKey

/**
 * Ключ мира: пара ECDSA P-256, от имени которой Мост подписывает карточки выдачи и ответы на вход (протокол Моста, разделы 6.4 и 8).
 * Публичная часть ([publicB64]) — получатель карточек сдачи на телефоне и значение `world_pub` в `hello` и `settings`.
 * Закрытая часть хранится в файле рядом с базой Моста и никуда не уходит; потеряли файл — телефоны не примут выдачу от нового ключа.
 */
class WorldKey(val publicB64: String, private val privateKey: PrivateKey) {
    fun sign(data: ByteArray): String = Ecdsa.sign(privateKey, data)

    companion object {
        /** Файл ключа для базы [dbPath]: `<база>.worldkey`; для `:memory:` файла нет (ключ живёт, пока жив процесс). */
        fun fileFor(dbPath: String): File? = if (dbPath == ":memory:") null else File("$dbPath.worldkey")

        fun generate(): WorldKey {
            val pair = Ecdsa.generateKeyPair()
            return WorldKey(Ecdsa.encodeKey(pair.public), pair.private)
        }

        /** Читает ключ из [file]; нет файла — создаёт новый атомарно (временный файл → перемещение) и возвращает его. */
        fun loadOrCreate(file: File): WorldKey {
            if (file.exists()) return read(file)
            val pair = Ecdsa.generateKeyPair()
            val tmp = File(file.path + ".tmp")
            tmp.writeText("${Ecdsa.encodeKey(pair.public)}\n${Ecdsa.encodeKey(pair.private)}\n")
            runCatching { Files.setPosixFilePermissions(tmp.toPath(), PosixFilePermissions.fromString("rw-------")) }
            Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            return WorldKey(Ecdsa.encodeKey(pair.public), pair.private)
        }

        private fun read(file: File): WorldKey {
            val lines = file.readLines().filter { it.isNotBlank() }
            require(lines.size == 2) { "файл ключа мира ${file.path} повреждён" }
            return WorldKey(lines[0], Ecdsa.decodePrivateKey(lines[1]))
        }
    }
}
