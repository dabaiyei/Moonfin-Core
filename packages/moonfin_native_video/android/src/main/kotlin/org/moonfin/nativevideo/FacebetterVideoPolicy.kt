package org.moonfin.nativevideo

internal object FacebetterVideoPolicy {
    fun bypassReason(width: Int, height: Int, range: String, frameRate: Float? = null): String? {
        val normalized = range.lowercase()
        return when {
            listOf("hdr", "dovi", "dolby", "hlg").any { normalized.contains(it) } -> "bypassHdr"
            maxOf(width, height) > 1920 || minOf(width, height) > 1080 -> "bypassResolution"
            frameRate != null && frameRate > 60.1f -> "bypassFrameRate"
            frameRate != null && frameRate > 30.1f &&
                (maxOf(width, height) > 1280 || minOf(width, height) > 720) -> "bypassFrameRate"
            else -> null
        }
    }
}
