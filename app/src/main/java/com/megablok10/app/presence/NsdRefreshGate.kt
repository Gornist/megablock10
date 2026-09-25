package com.megablok10.app.presence

/**
 * Когда пересоздавать NSD-регистрацию по событию WifiBinder. Раньше — на каждое: при запуске процесса приходят `wifi.available`
 * (первая привязка, NSD к этому времени уже стартовал) и сразу `wifi.link_changed` с тем же IP, и за 100 мс регистрация снималась
 * и ставилась трижды. Незавершённая регистрация при этом теряется: e2e A4 (run 36179242929) — из 26 `nsd.start` лишь 3
 * `nsd.registered`, после перезапуска Alice её новый порт так и не был объявлен, и кэш mDNS у Bob отдавал порт прошлого процесса;
 * run 36189865402 (wifi-bind) — после перезапуска обоих ни одного `nsd.registered`, друг друга не нашли за 30 с.
 *
 * Теперь: сеть и IP те же, что при последнем (пере)запуске, — ничего не делать; первая привязка к Wi-Fi после [started] без сети —
 * просто запомнить (NSD системный, объявляет на появившемся интерфейсе сам); иначе — это смена сети, пересоздать.
 * Чистая логика без Android — ключ сети любой (в приложении — Network и IPv4).
 */
class NsdRefreshGate<N : Any> {
    private var network: N? = null
    private var ip: String? = null
    private var adoptFirstNetwork = false

    /** NSD запущен заново извне (сессия), [network]/[ip] — что было на тот момент (null — Wi-Fi ещё не привязан). */
    fun started(network: N?, ip: String?) {
        this.network = network; this.ip = ip
        adoptFirstNetwork = network == null
    }

    /** Пришло событие сети: true — пересоздать NSD (и запомнить новое состояние), false — пропустить. */
    fun shouldRefresh(network: N?, ip: String?): Boolean {
        if (network == this.network && ip == this.ip) return false
        val adopt = adoptFirstNetwork && this.network == null && network != null
        this.network = network; this.ip = ip
        adoptFirstNetwork = false
        return !adopt
    }
}
