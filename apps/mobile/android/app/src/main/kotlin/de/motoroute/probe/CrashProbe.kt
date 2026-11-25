package de.motoroute.probe

/**
 * Absichtlicher Absturz fuer den R8-Mapping-Beweis (scripts/verify-r8-mapping.sh).
 *
 * Das Paket liegt bewusst ausserhalb von `de.motoroute.app`: proguard-rules.pro
 * keept dieses Paket vollstaendig, hier soll R8 dagegen umbenennen. Nur so
 * zeigt der Stacktrace verschleierte Namen und das Mapping beweist etwas.
 *
 * Erreicht wird die Sonde nur, wenn der Build mit -PcrashProbe=true gebaut und
 * der Start mit dem Extra `crash_probe` ausgeloest wurde.
 */
internal object CrashProbe {
    fun trigger() {
        explode(null)
    }

    private fun explode(value: String?) {
        throw IllegalStateException("R8-Probe v2: " + value!!.length)
    }
}
