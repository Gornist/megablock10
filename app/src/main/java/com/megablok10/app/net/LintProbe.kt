package com.megablok10.app.net

// ВРЕМЕННАЯ ПРОБА (откатывается следующим коммитом): тот же вызов, что ронял отправку на Android 8–12 (e7a31ae) —
// конструктор PrintWriter(OutputStream, Boolean, Charset) есть только с API 33. Шаг CI «Android Lint — NewApi» обязан упасть.
internal fun lintProbe(out: java.io.OutputStream) = java.io.PrintWriter(out, true, Charsets.UTF_8)
