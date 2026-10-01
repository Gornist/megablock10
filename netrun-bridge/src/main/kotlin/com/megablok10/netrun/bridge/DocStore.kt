package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.sql.Connection
import java.sql.DriverManager

/**
 * Хранилище документов: всё в памяти, каждое изменение — транзакцией в SQLite, при открытии читается обратно.
 *
 * Память меняется только после успешного коммита SQLite, поэтому оборванная транзакция не оставляет половины ни там, ни там.
 * Сквозной счётчик [seq] хранится в SQLite и продолжается после перезапуска; одна транзакция получает один `seq`.
 * Операции с ценностями (B3) и правила (B2) строятся поверх [transaction]; подписчики (B1) — через [addListener].
 */
class DocStore private constructor(
    private val conn: Connection,
    private val clock: () -> Long,
) : AutoCloseable {
    private val docs = HashMap<DocKey, Doc>()
    private var seqValue = 0L
    private val listeners = ArrayList<(List<Change>) -> Unit>()

    /** Номер последнего изменения. */
    val seq: Long @Synchronized get() = seqValue

    @Synchronized
    fun get(type: String, id: String): Doc? = docs[DocKey(type, id)]

    @Synchronized
    fun list(type: String): List<Doc> = docs.values.filter { it.type == type }.sortedBy { it.id }

    /** Снимок типов и `seq` на один момент (для `sub`/`list`). */
    @Synchronized
    fun snapshot(types: Set<String>): Pair<Long, List<Doc>> =
        seqValue to docs.values.filter { it.type in types }.sortedWith(compareBy({ it.type }, { it.id }))

    /**
     * Подписка на изменения: вызывается после коммита, под замком хранилища, поэтому порядок вызовов совпадает с порядком
     * `seq`. Слушатель не должен блокироваться и не должен писать в хранилище из того же потока.
     */
    @Synchronized
    fun addListener(l: (List<Change>) -> Unit) {
        listeners.add(l)
    }

    /** Запись с проверкой версии: [ver] = 0 — создать, иначе версия, которую клиент видел. `data` заменяется целиком. */
    fun put(type: String, id: String, ver: Long, data: JsonObject): Doc =
        transaction { it.put(type, id, ver, data) }

    fun delete(type: String, id: String, ver: Long) {
        transaction { it.delete(type, id, ver) }
    }

    /**
     * Одна транзакция: либо все изменения [block] и один новый `seq`, либо ничего (исключение откатывает всё).
     * Внутри читать нужно через [Tx.get], чтобы видеть собственные записи.
     */
    @Synchronized
    fun <T> transaction(block: (Tx) -> T): T {
        val tx = Tx()
        val result = block(tx)
        if (tx.order.isEmpty()) return result
        val newSeq = seqValue + 1
        val changes = commit(tx, newSeq)
        // Только теперь, когда SQLite подтвердил, — память и слушатели.
        for (c in changes) if (c.deleted) docs.remove(DocKey(c.doc.type, c.doc.id)) else docs[DocKey(c.doc.type, c.doc.id)] = c.doc
        seqValue = newSeq
        listeners.forEach { it(changes) }
        return result
    }

    private fun commit(tx: Tx, newSeq: Long): List<Change> {
        val keys = tx.order
        val changes = keys.mapIndexed { i, k ->
            val p = tx.pending.getValue(k)
            Change(newSeq, i == keys.lastIndex, p.doc, p.deleted)
        }
        conn.autoCommit = false
        try {
            for (c in changes) {
                if (c.deleted) {
                    conn.prepareStatement("DELETE FROM docs WHERE type=? AND id=?").use {
                        it.setString(1, c.doc.type); it.setString(2, c.doc.id); it.executeUpdate()
                    }
                } else {
                    conn.prepareStatement(
                        "INSERT OR REPLACE INTO docs(type,id,ver,created,updated,data) VALUES (?,?,?,?,?,?)",
                    ).use {
                        it.setString(1, c.doc.type); it.setString(2, c.doc.id); it.setLong(3, c.doc.ver)
                        it.setLong(4, c.doc.created); it.setLong(5, c.doc.updated); it.setString(6, c.doc.data.toString())
                        it.executeUpdate()
                    }
                }
            }
            conn.prepareStatement("INSERT OR REPLACE INTO meta(key,value) VALUES ('seq',?)").use {
                it.setLong(1, newSeq); it.executeUpdate()
            }
            conn.commit()
        } catch (e: java.sql.SQLException) {
            runCatching { conn.rollback() }
            throw StoreException("internal", "сбой SQLite: ${e.message}")
        } finally {
            conn.autoCommit = true
        }
        return changes
    }

    @Synchronized
    override fun close() {
        conn.close()
    }

    internal class Pending(val doc: Doc, val deleted: Boolean)

    /** Изменения одной транзакции; все записи видны только внутри неё до коммита. */
    inner class Tx internal constructor() {
        internal val pending = HashMap<DocKey, Pending>()
        internal val order = ArrayList<DocKey>()

        fun get(type: String, id: String): Doc? {
            val k = DocKey(type, id)
            val p = pending[k]
            return if (p != null) p.doc.takeUnless { p.deleted } else docs[k]
        }

        fun put(type: String, id: String, ver: Long, data: JsonObject): Doc {
            requireKey(type, id)
            val cur = get(type, id)
            val now = clock()
            val doc = when {
                ver == 0L && cur != null -> throw StoreException("exists", "документ уже есть", cur)
                ver == 0L -> Doc(type, id, 1, now, now, data)
                cur == null -> throw StoreException("not_found", "документа нет")
                cur.ver != ver -> throw StoreException("version_conflict", "версия ${cur.ver}, а не $ver", cur)
                else -> cur.copy(ver = cur.ver + 1, updated = now, data = data)
            }
            record(doc, false)
            return doc
        }

        fun delete(type: String, id: String, ver: Long) {
            requireKey(type, id)
            val cur = get(type, id) ?: throw StoreException("not_found", "документа нет")
            if (cur.ver != ver) throw StoreException("version_conflict", "версия ${cur.ver}, а не $ver", cur)
            record(cur, true)
        }

        private fun requireKey(type: String, id: String) {
            if (!isValidType(type) || !isValidId(id)) throw StoreException("bad_request", "неверный type или id")
        }

        private fun record(doc: Doc, deleted: Boolean) {
            val k = DocKey(doc.type, doc.id)
            if (k !in pending) order.add(k)
            pending[k] = Pending(doc, deleted)
        }
    }

    companion object {
        /** Открывает базу [path] (или `:memory:`), создаёт таблицы и читает документы в память. */
        fun open(path: String, clock: () -> Long = System::currentTimeMillis): DocStore {
            val conn = DriverManager.getConnection("jdbc:sqlite:$path")
            try {
                conn.createStatement().use {
                    it.execute("PRAGMA journal_mode=WAL")
                    it.execute("PRAGMA synchronous=FULL")
                    it.execute(
                        "CREATE TABLE IF NOT EXISTS docs(type TEXT NOT NULL, id TEXT NOT NULL, ver INTEGER NOT NULL, " +
                            "created INTEGER NOT NULL, updated INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(type,id))",
                    )
                    it.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
                }
                val store = DocStore(conn, clock)
                store.load()
                return store
            } catch (e: Exception) {
                conn.close()
                throw e
            }
        }
    }

    private fun load() {
        conn.createStatement().use { st ->
            st.executeQuery("SELECT type,id,ver,created,updated,data FROM docs").use { rs ->
                while (rs.next()) {
                    val data = Json.parseToJsonElement(rs.getString(6)) as JsonObject
                    docs[DocKey(rs.getString(1), rs.getString(2))] =
                        Doc(rs.getString(1), rs.getString(2), rs.getLong(3), rs.getLong(4), rs.getLong(5), data)
                }
            }
            st.executeQuery("SELECT value FROM meta WHERE key='seq'").use { rs -> if (rs.next()) seqValue = rs.getLong(1) }
        }
    }
}
