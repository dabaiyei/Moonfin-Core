package org.moonfin.nativevideo

import android.os.Build

/** Immutable snapshots shared by the platform-channel and GL threads. */
internal data class FacebetterSettings(
    val enabled: Boolean = false,
    val smoothing: Float = 0.35f,
    val whitening: Float = 0.2f,
    val rosiness: Float = 0.1f,
    val sharpening: Float = 0.15f,
    val faceThin: Float = 0f,
    val eyeSize: Float = 0f,
) {
    companion object {
        fun fromWire(args: Map<*, *>): FacebetterSettings {
            fun strength(key: String, fallback: Float): Float {
                val value = (args[key] as? Number)?.toFloat() ?: fallback
                return if (value.isFinite()) value.coerceIn(0f, 1f) else fallback
            }
            return FacebetterSettings(
                enabled = args["enabled"] == true,
                smoothing = strength("smoothing", 0.35f),
                whitening = strength("whitening", 0.2f),
                rosiness = strength("rosiness", 0.1f),
                sharpening = strength("sharpening", 0.15f),
                faceThin = strength("faceThin", 0f),
                eyeSize = strength("eyeSize", 0f),
            )
        }
    }
}

internal data class FacebetterCredentials(
    val licenseToken: String = BuildConfig.FACEBETTER_LICENSE_TOKEN,
    val appId: String = BuildConfig.FACEBETTER_APP_ID,
    val appKey: String = BuildConfig.FACEBETTER_APP_KEY,
) {
    val configured: Boolean get() = licenseToken.isNotBlank() || (appId.isNotBlank() && appKey.isNotBlank())
    companion object {
        fun fromWire(args: Map<*, *>) = FacebetterCredentials(
            args["licenseToken"] as? String ?: "",
            args["appId"] as? String ?: "",
            args["appKey"] as? String ?: "",
        )
    }
}

internal object FacebetterRuntime {
    @Volatile var settings = FacebetterSettings()
        private set
    @Volatile private var status = "disabled"
    @Volatile var credentials = FacebetterCredentials()
        private set
    @Volatile var credentialRevision = 0L
        private set

    val configured: Boolean
        get() = credentials.configured

    private val supported: Boolean
        get() = Build.VERSION.SDK_INT >= 24 &&
            Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "armeabi-v7a" }

    fun shouldAttach(role: String): Boolean =
        role != "preview" && settings.enabled && configured && supported

    fun update(args: Map<*, *>) {
        val previous = settings
        val nextCredentials = (args["license"] as? Map<*, *>)?.let { FacebetterCredentials.fromWire(it) }
        val changed = nextCredentials != null && nextCredentials != credentials
        if (changed) {
            credentials = checkNotNull(nextCredentials)
            credentialRevision++
        }
        settings = FacebetterSettings.fromWire(args)
        when {
            !settings.enabled -> report("disabled")
            !configured -> report("missingLicense")
            !supported -> report("unsupportedDevice")
            !previous.enabled || changed -> report("waiting")
        }
    }

    fun snapshot(): Map<String, Any?> = mapOf(
        "event" to "beautyStatus",
        "status" to status,
        "configured" to configured,
    )

    fun report(value: String) {
        if (!settings.enabled && value != "disabled") return
        if (status == value) return
        status = value
        Media3Bridge.emitEvent(snapshot())
    }
}
