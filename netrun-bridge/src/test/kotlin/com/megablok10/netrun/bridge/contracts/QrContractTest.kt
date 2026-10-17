package com.megablok10.netrun.bridge.contracts

import com.megablok10.netrun.bridge.phone.PhoneWire
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Сигнал СБ Моста (`PhoneWire.encodeSecAlert`) против `qr.json`. Остальные виды — контейнер, шард, RAM-апгрейд, персонаж — Мост не кодирует и не
 * разбирает (их печатает Мастерская, читает приложение), поэтому здесь их нет; разбора `SECALERT` в Мосте тоже нет — он только отправитель.
 */
class QrContractTest {
    private val vectors = ContractVectors.load("qr.json")

    @Test fun строкиСигналаСб() {
        val all = vectors.list("secAlerts")
        assertTrue(all.isNotEmpty())
        for (v in all) {
            val line = PhoneWire.encodeSecAlert(v.str("containerId"), v.str("containerName"), v.long("tier").toInt(), v.strOrNull("intruderCallsign"), v.strOrNull("preciseAt")?.toLong())
            assertEquals(v.str("name"), v.str("line"), line)
        }
    }
}
