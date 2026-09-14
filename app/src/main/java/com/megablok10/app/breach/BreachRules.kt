package com.megablok10.app.breach

/**
 * Правило чередования строка/столбец из оригинала Cyberpunk 2077: после
 * первого выбора (всегда из верхней строки) вторая клетка обязана быть в
 * том же СТОЛБЦЕ, третья — в той же СТРОКЕ, что вторая, и так далее.
 *
 * Это ЕДИНСТВЕННОЕ место, где определена эта связка. И генератор сетки
 * (BreachEngine.generateGrid), и экран (BreachUiState.selectableCells)
 * обязаны брать её отсюда, а не дублировать — иначе гарантия решаемости
 * молча ломается: генератор проложит путь по одному правилу, а игрок
 * будет ограничен другим, и решение окажется физически недостижимым.
 */
enum class LinkDimension { ROW, COLUMN }

/** selectedCount — сколько клеток уже выбрано (>=1). Возвращает ограничение для СЛЕДУЮЩЕЙ. */
fun nextLinkDimension(selectedCount: Int): LinkDimension =
    if ((selectedCount - 1) % 2 == 0) LinkDimension.COLUMN else LinkDimension.ROW

/** Ещё не посещённые клетки той же строки/столбца, что и `from`, кроме самой `from`. */
fun candidatesFor(
    from: Pair<Int, Int>,
    dimension: LinkDimension,
    gridSize: Int,
    visited: Set<Pair<Int, Int>>
): List<Pair<Int, Int>> {
    val (row, col) = from
    val all = if (dimension == LinkDimension.COLUMN) {
        (0 until gridSize).map { r -> r to col }
    } else {
        (0 until gridSize).map { c -> row to c }
    }
    return all.filter { it != from && it !in visited }
}
