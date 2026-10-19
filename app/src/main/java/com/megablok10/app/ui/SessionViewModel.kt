package com.megablok10.app.ui

import androidx.lifecycle.ViewModel
import com.megablok10.app.PlayerNotices
import com.megablok10.app.collector.RedeemResult
import com.megablok10.app.identity.CreateCharacter
import com.megablok10.app.identity.Identity
import com.megablok10.app.identity.IdentityStore
import com.megablok10.app.qr.Mb10Qr
import com.megablok10.app.qr.Mb10QrCodec
import com.megablok10.app.qr.ProvisionCode
import com.megablok10.app.qr.ProvisionResult
import com.megablok10.kit.mesh.OnlinePlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Состояние корня приложения (AppRoot): есть ли персонаж, выдача по QR мастера, ручное создание, сброс сессии, узлы сети в шапке.
 * Сетевая сессия поднимается отдельно, при запуске процесса — [com.megablok10.app.session.SessionController] (AppGraph.startSession),
 * не завязана на этот экран (см. docs/android-handoff.md, «Сетевая сессия от процесса»).
 *
 * Выдача, создание и сброс идут в [work] (скоуп процесса), а не в скоупе экрана: их нельзя бросить на полпути, даже если
 * экран за это время сменился или Activity пересоздалась.
 */
class SessionViewModel(
    private val identityStore: IdentityStore,
    val peers: StateFlow<List<OnlinePlayer>>,
    private val provisioning: suspend (Mb10Qr.Provision) -> ProvisionResult,
    /** Обмен короткого кода на QR у коллектора (CollectorClient.redeemProvisionCode). */
    private val redeem: suspend (baseUrl: String, code: String) -> RedeemResult,
    /** Адрес сервера, уже известный телефону (сборка или прошлая выдача), — CollectorSettings.baseUrl. */
    private val savedBaseUrl: () -> String?,
    private val create: CreateCharacter,
    private val reset: suspend (Identity?) -> Unit,
    onUiStarted: () -> Unit,
    private val notices: PlayerNotices,
    private val work: CoroutineScope,
) : ViewModel() {
    /** Личность реактивна: создание, сброс и правки мастера (позывной, фракция, RAM) видны сразу. */
    val identity: StateFlow<Identity?> = identityStore.state

    init {
        onUiStarted()
    }

    /** Адреса сервера ещё нет (ни из сборки, ни от прошлой выдачи) — экрану первого запуска нужно поле «Адрес сервера». */
    fun needsServerAddress(): Boolean = savedBaseUrl() == null

    fun provision(qr: Mb10Qr.Provision) {
        work.launch { applyProvision(qr) }
    }

    /**
     * Ввод короткого кода без камеры: код → QR (сервер мастера) → та же выдача, что и по сканированию. Ввод, который не код, на
     * сервер не уходит вовсе — неверные попытки жгут его лимит. [serverAddress] нужен, только пока сохранённого адреса нет.
     */
    fun redeemCode(input: String, serverAddress: String) {
        work.launch {
            val code = ProvisionCode.normalize(input)
            if (code == null) {
                notices.show("Код — 6 знаков: буквы и цифры 2–9, без O, I, L")
                return@launch
            }
            val baseUrl = savedBaseUrl() ?: normalizeServerAddress(serverAddress)
            if (baseUrl == null) {
                notices.show("Введите адрес сервера мастера")
                return@launch
            }
            when (val result = redeem(baseUrl, code)) {
                is RedeemResult.Qr -> {
                    val provision = Mb10QrCodec.decode(result.qr) as? Mb10Qr.Provision
                    if (provision == null) notices.show("Сервер вернул непонятный код — обратитесь к мастеру")
                    // Пустой адрес в QR значит «как в сборке»; у телефона без адреса в сборке оставить пустым нельзя — подставляем тот, по которому достучались.
                    else applyProvision(if (provision.collectorUrl.isEmpty()) provision.copy(collectorUrl = baseUrl) else provision)
                }
                RedeemResult.UnknownCode -> notices.show("Код не найден или уже использован. Проверьте код или попросите мастера выдать новый")
                is RedeemResult.RateLimited -> notices.show("Слишком много попыток. Повторите через ${waitText(result.retryAfterSec)}")
                RedeemResult.Unsupported -> notices.show("Сервер не поддерживает ввод кода — отсканируйте QR")
                RedeemResult.Unreachable -> notices.show("Нет связи с сервером мастера. Проверьте Wi-Fi и адрес")
            }
        }
    }

    private suspend fun applyProvision(qr: Mb10Qr.Provision) {
        val message = when (val result = provisioning(qr)) {
            is ProvisionResult.Applied -> null // личность появилась в IdentityStore.state — экран сменится сам
            ProvisionResult.AlreadyHasIdentity -> "Персонаж уже создан. Повторно — только после сброса сессии в Настройках"
            ProvisionResult.AlreadyUsed -> "Этот код уже использован. Попросите мастера выдать новый"
            is ProvisionResult.Invalid -> result.message
        }
        message?.let(notices::show)
    }

    private fun waitText(seconds: Int): String = if (seconds >= 60) "${(seconds + 59) / 60} мин" else "$seconds с"

    /** Введённый адрес → базовый URL: схема `http://` по умолчанию (сеть игры без TLS), хвостовой «/» не нужен. Пусто — null. */
    private fun normalizeServerAddress(input: String): String? {
        val trimmed = input.trim().trimEnd('/')
        if (trimmed.isEmpty()) return null
        return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) trimmed else "http://$trimmed"
    }

    fun createCharacter(callsign: String, faction: String) {
        work.launch { create(callsign, faction) }
    }

    /** Полный сброс сессии на устройстве (identity/SessionReset): записи о сбросе уходят мастеру до стирания ключа. */
    fun resetSession() {
        work.launch { reset(identityStore.current) }
    }
}
