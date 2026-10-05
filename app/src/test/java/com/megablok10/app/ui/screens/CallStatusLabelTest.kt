package com.megablok10.app.ui.screens

import com.megablok10.app.call.CallUiState
import org.junit.Assert.assertEquals
import org.junit.Test

/** Подпись звонка: «СОЕДИНЕНИЕ» только пока он ещё не соединялся; потеряв связь — говорим об этом, а не показываем то же самое вечно. */
class CallStatusLabelTest {
    @Test fun connectingBeforeFirstConnection() = assertEquals("СОЕДИНЕНИЕ", callStatusLabel(CallUiState()))

    @Test fun onAirWhenConnected() = assertEquals("В ЭФИРЕ", callStatusLabel(CallUiState(audioConnected = true, everConnected = true)))

    @Test fun reconnectingAfterLoss() =
        assertEquals("СВЯЗЬ ПОТЕРЯНА · ВОССТАНАВЛИВАЕМ", callStatusLabel(CallUiState(audioConnected = false, everConnected = true)))
}
