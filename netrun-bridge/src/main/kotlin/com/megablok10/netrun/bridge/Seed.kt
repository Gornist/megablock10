package com.megablok10.netrun.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/**
 * Начальные документы для стенда (`--seed файл.json`, только вместе с `--test`): `{"тип": {"id": {…data…}}}`.
 * Минует защиту ценностей — так на стенде без телефона появляются предметы, сессия и дека. Нет документа — создаётся;
 * есть — поля из файла дописываются к существующим (так стенд ускоряет аудитор, не теряя `world_pub` настроек).
 * Повторный запуск с тем же файлом ничего не меняет по сути: рестарт Моста на стенде не затирает забег.
 */
internal fun seedDocs(store: DocStore, text: String): Int {
    var n = 0
    for ((type, byId) in Json.parseToJsonElement(text).jsonObject) {
        for ((id, data) in byId.jsonObject) {
            val cur = store.get(type, id)
            if (cur == null) {
                store.put(type, id, 0, data.jsonObject)
                n++
            } else if (type == "settings") {
                store.put(type, id, cur.ver, JsonObject(cur.data + data.jsonObject))
                n++
            }
        }
    }
    return n
}
