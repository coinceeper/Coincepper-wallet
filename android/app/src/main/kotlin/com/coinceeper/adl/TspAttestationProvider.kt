package com.coinceeper.adl

import android.content.Context

/** Stub: real implementation built by Go + NDK (build_gobridge.sh). */
object TspAttestationProvider {
    @JvmStatic
    fun getPlayIntegrityToken(context: Context, nonceHint: String, callback: (String) -> Unit) {
        callback("")
    }
}
