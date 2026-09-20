package com.megablok10.app.ui

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Дизайн-язык приложения — скошенные рамки. Голый `Modifier.border(w, color)` рисует прямоугольник и выбивается из него,
 * поэтому в исходниках допустим только `.border(..., <форма>)` или `chamferBorder(...)`.
 */
class NoRectangularBordersTest {
    @Test
    fun everyBorderHasAShape() {
        val root = File("src/main/java")
        assertTrue("нет каталога исходников: ${root.absolutePath}", root.isDirectory)
        val offenders = root.walkTopDown().filter { it.extension == "kt" }.flatMap { file ->
            file.readLines().mapIndexedNotNull { i, line ->
                val code = line.trim()
                val isComment = code.startsWith("*") || code.startsWith("//") || code.startsWith("/*")
                if (!isComment && ".border(" in code && "hape" !in code) "${file.name}:${i + 1}: $code" else null
            }
        }.toList()
        assertTrue("прямоугольные рамки (используйте chamferBorder):\n" + offenders.joinToString("\n"), offenders.isEmpty())
    }
}
