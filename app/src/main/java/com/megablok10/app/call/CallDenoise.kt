package com.megablok10.app.call

/**
 * Включён ли нейросетевой шумодав микрофона звонка (RNNoise). По умолчанию да; выключатель — отладочная команда `DEBUG_SET --es callaudio "rnnoise=0"` (только debug-сборка):
 * сравнить на слух «со шумодавом / только штатное» при жалобе, без пересборки. Читается на лету (bypass-флаг обработчика), звонок перезапускать не нужно.
 */
object CallDenoise {
    @Volatile var enabled: Boolean = true

    /** Разбор `rnnoise=0|1` (остальные ключи игнорируются; пусто — значения по умолчанию). */
    fun apply(spec: String) {
        enabled = true
        spec.split(',').map { it.trim() }.forEach { pair ->
            if (pair.substringBefore('=') == "rnnoise") enabled = pair.substringAfter('=', "") != "0"
        }
    }
}
