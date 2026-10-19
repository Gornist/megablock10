package com.megablok10.app.qr

/**
 * Короткий код выдачи персонажа — запасной путь, когда у телефона нет камеры (решение владельца 19.10): 6 знаков, печатается
 * как `ABC-DEF`, выдаёт коллектор рядом с QR. Телефон и сервер нормализуют ввод одинаково (общие векторы —
 * `rules/src/test/resources/contracts/provision-code.json`); всё, что после нормализации не код, на сервер не уходит — неверные
 * попытки жгут его лимит, а подбор по честному коду всё равно не ограничен ничем, кроме этого лимита.
 *
 * В алфавите нет I, L, O и цифр 0, 1: на бумаге и экране их путают.
 */
object ProvisionCode {
    const val ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    const val LENGTH = 6

    /** Код без разделителей в верхнем регистре, либо null — ввод не код (пробелы и «-» отбрасываются, прочее не меняется). */
    fun normalize(input: String): String? {
        val code = input.filterNot { it == '-' || it.isWhitespace() }.uppercase()
        return code.takeIf { it.length == LENGTH && it.all { ch -> ch in ALPHABET } }
    }

    /** Вид для показа: `ABC-DEF`. Принимает уже нормализованный код. */
    fun format(code: String): String = if (code.length == LENGTH) code.substring(0, 3) + "-" + code.substring(3) else code
}
