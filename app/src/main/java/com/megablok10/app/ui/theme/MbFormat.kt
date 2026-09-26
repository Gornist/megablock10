package com.megablok10.app.ui.theme

/** Деньги в формате гайдлайна (раздел 7): `1 240 €$`, узкий неразрывный пробел между разрядами тысяч, минус — знаком «−». */
fun formatMoney(amount: Long): String {
    val grouped = kotlin.math.abs(amount).toString().reversed().chunked(3).joinToString(" ").reversed()
    return (if (amount < 0) "−" else "") + grouped + " €$"
}
