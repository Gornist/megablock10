package com.megablok10.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.megablok10.app.di.appGraph
import com.megablok10.app.headset.HeadsetConfig
import com.megablok10.app.ui.theme.LocalMbColors
import com.megablok10.app.ui.theme.MbButton
import com.megablok10.app.ui.theme.MbButtonKind
import com.megablok10.app.ui.theme.MbDimens
import com.megablok10.app.ui.theme.MbField
import com.megablok10.app.ui.theme.MbFormRow
import com.megablok10.app.ui.theme.MbSectionTitle
import com.megablok10.app.ui.theme.MbToggle
import com.megablok10.app.ui.theme.MbTypography

/** Секция «Очки» экрана «Сеть»: берёт настройки из графа приложения и отдаёт их в [HeadsetSectionContent]. */
@Composable
internal fun HeadsetSection() {
    val settings = LocalContext.current.appGraph.headsetSettings
    val config by settings.config.collectAsStateWithLifecycle()
    HeadsetSectionContent(config = config, onChange = settings::update)
}

/**
 * Связь с очками Pico (docs/netrun-phone-link.md, срез 1): переключатель, адрес очков (`host` или `host:порт`, порт по умолчанию 7420) и токен канала.
 * Включено ли — отдельный выбор; адрес и токен сохраняются кнопкой, чтобы не переподключаться на каждый набранный символ.
 */
@Composable
internal fun HeadsetSectionContent(config: HeadsetConfig, onChange: ((HeadsetConfig) -> HeadsetConfig) -> Unit) {
    val c = LocalMbColors.current
    var address by remember(config.address) { mutableStateOf(config.address) }
    var token by remember(config.token) { mutableStateOf(config.token) }
    Column(verticalArrangement = Arrangement.spacedBy(MbDimens.blockGap)) {
        MbSectionTitle("Очки Pico", meta = if (config.enabled) (if (config.url() != null) "включено" else "не настроено") else "выключено")
        Text(
            "Второй экран: сообщения и звонки телефона видны в очках, ответ — заготовками. Телефон подключается к очкам сам (адрес и токен показывают очки); " +
                "пока очки на связи, звуки сообщений и звонков играют в них.",
            style = MbTypography.meta, color = c.ink2
        )
        MbFormRow("Связь с очками") { MbToggle(config.enabled, { on -> onChange { it.copy(enabled = on) } }) }
        MbFormRow("Голос звонка в очках (проба)") { MbToggle(config.voiceEnabled, { on -> onChange { it.copy(voiceEnabled = on) } }) }
        if (config.voiceEnabled) {
            Text(
                "Микрофон и динамики очков вместо телефона во время звонка; пропал звук очков — звонок сам возвращается на телефон. " +
                    "Нужен включённый звонок в очках и микрофон в них.",
                style = MbTypography.meta, color = c.ink2
            )
        }
        MbField(value = address, onValueChange = { address = it }, placeholder = "адрес очков: 192.168.1.50:7420")
        MbField(value = token, onValueChange = { token = it }, placeholder = "токен (латиница, цифры, - и _)")
        MbButton(
            "Сохранить адрес и токен", kind = MbButtonKind.Ghost,
            onClick = { onChange { it.copy(address = address.trim(), token = token.trim()) } }
        )
        if (config.enabled && config.url() == null) {
            Text("Адрес или токен не годятся: адрес — host или host:порт, токен — латиница, цифры, - и _.", style = MbTypography.meta, color = c.bad)
        }
    }
}
