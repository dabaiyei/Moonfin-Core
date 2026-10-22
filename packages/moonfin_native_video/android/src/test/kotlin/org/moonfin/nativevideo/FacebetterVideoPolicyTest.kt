package org.moonfin.nativevideo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FacebetterVideoPolicyTest {
    @Test fun permitsSdrWithinDocumentedLimits() {
        assertNull(FacebetterVideoPolicy.bypassReason(1920, 1080, "SDR", 29.97f))
        assertNull(FacebetterVideoPolicy.bypassReason(720, 1280, "SDR", 59.94f))
        assertNull(FacebetterVideoPolicy.bypassReason(0, 0, "", null))
    }

    @Test fun bypassesHdrAndDolbyVisionWithoutChangingTheirColorPipeline() {
        for (range in listOf("HDR10", "HLG", "DOVIWithHDR10", "DolbyVision")) {
            assertEquals("bypassHdr", FacebetterVideoPolicy.bypassReason(1920, 1080, range))
        }
    }

    @Test fun limitsAlsoApplyToPortraitAndHighFrameRateVideo() {
        assertEquals("bypassResolution", FacebetterVideoPolicy.bypassReason(2160, 3840, "SDR"))
        assertEquals("bypassFrameRate", FacebetterVideoPolicy.bypassReason(1920, 1080, "SDR", 59.94f))
        assertEquals("bypassFrameRate", FacebetterVideoPolicy.bypassReason(640, 480, "SDR", 120f))
    }

    @Test fun wireValuesCannotSendInvalidStrengthsToNativeSdk() {
        val settings = FacebetterSettings.fromWire(mapOf(
            "enabled" to true, "smoothing" to Double.NaN,
            "whitening" to 20, "faceThin" to -1, "eyeSize" to Double.POSITIVE_INFINITY,
        ))
        assertEquals(0.35f, settings.smoothing, 0f)
        assertEquals(1f, settings.whitening, 0f)
        assertEquals(0f, settings.faceThin, 0f)
        assertEquals(0f, settings.eyeSize, 0f)
    }
}
