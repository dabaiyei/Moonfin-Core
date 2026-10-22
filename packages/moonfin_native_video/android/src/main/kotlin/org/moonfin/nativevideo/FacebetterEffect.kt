package org.moonfin.nativevideo

import android.content.Context
import android.opengl.GLES20
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.Contrast
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import net.pixpark.facebetter.BeautyEffectEngine
import net.pixpark.facebetter.BeautyParams.Reshape
import net.pixpark.facebetter.EngineCallbacks
import net.pixpark.facebetter.EngineEventCode
import net.pixpark.facebetter.ImageFrame

/** Runs only on Media3's GL thread, between decoding and final display. */
internal class FacebetterEffect : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        // Facebetter accepts 8-bit RGBA, not linear BT.2020 HDR textures.
        if (useHdr) {
            FacebetterRuntime.report("bypassHdr")
            return Contrast(0f).toGlShaderProgram(context, true)
        }
        return try {
            FacebetterShaderProgram(context.applicationContext)
        } catch (_: Exception) {
            FacebetterRuntime.report("failed")
            Contrast(0f).toGlShaderProgram(context, false)
        }
    }
}

private class FacebetterShaderProgram(private val context: Context) : BaseGlShaderProgram(false, 1) {
    private val copy = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER).apply {
        setBufferAttribute("aPosition", floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f), 2)
    }
    private var width = 0
    private var height = 0
    private var inputTexture = 0
    private var inputFramebuffer = 0
    private var engine: BeautyEffectEngine? = null
    private var applied: FacebetterSettings? = null
    private var failed = false
    private var basicOnly = false
    private var initializationStartedMs = 0L
    @Volatile private var ready = false
    @Volatile private var released = false
    @Volatile private var initializationFailed = false
    @Volatile private var credentialRevision = -1L

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        deleteInputTarget()
        return Size(width, height)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        val framebuffer = IntArray(1)
        val viewport = IntArray(4)
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, framebuffer, 0)
        GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, viewport, 0)
        var input: ImageFrame? = null
        var output: ImageFrame? = null
        var texture = inputTexId
        var decodeSrgb = false
        try {
            if (credentialRevision != FacebetterRuntime.credentialRevision) {
                credentialRevision = FacebetterRuntime.credentialRevision
                engine?.release()
                engine = null
                applied = null
                ready = false
                failed = false
                initializationFailed = false
            }
            val settings = FacebetterRuntime.settings
            val withinLimit = maxOf(width, height) <= 1920 && minOf(width, height) <= 1080
            if (!withinLimit) {
                FacebetterRuntime.report("bypassResolution")
            } else if (settings.enabled && !failed) {
                val beauty = ensureEngine()
                if (beauty != null && !ready && !initializationFailed) {
                    // Setters may accept parameters before models/authentication
                    // finish. Only the initialization event permits processing.
                    if (SystemClock.elapsedRealtime() - initializationStartedMs > 15_000) {
                        initializationFailed = true
                    }
                }
                if (initializationFailed) {
                    failed = true
                    FacebetterRuntime.report("failed")
                } else if (beauty != null && ready && applySettings(beauty, settings)) {
                    ensureInputTarget()
                    GlUtil.focusFramebufferUsingCurrentContext(inputFramebuffer, width, height)
                    // Media3 effects receive linear RGB. Encode before handing
                    // it to the SDK, then decode its result back to linear RGB.
                    blit(inputTexId, 1)
                    input = ImageFrame.createWithTexture(inputTexture, width, height, width * 4)
                    checkNotNull(input) { "Facebetter input frame allocation failed" }
                    input.type = ImageFrame.FrameType.VIDEO
                    output = beauty.processImage(input)
                    checkNotNull(output) { "Facebetter returned no output frame" }
                    check(output.texture > 0) { "Facebetter returned no output texture" }
                    texture = output.texture
                    decodeSrgb = true
                    FacebetterRuntime.report(if (basicOnly) "readyBasicOnly" else "ready")
                }
            }
        } catch (error: Exception) {
            fail(error)
        } catch (error: LinkageError) {
            // A missing or incompatible native ABI must not abort playback.
            fail(error)
        }
        try {
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, framebuffer[0])
            GLES20.glViewport(viewport[0], viewport[1], viewport[2], viewport[3])
            blit(texture, if (decodeSrgb) 2 else 0)
        } catch (error: GlUtil.GlException) {
            throw VideoFrameProcessingException(error, presentationTimeUs)
        } finally {
            // The SDK owns its output texture. Keep its frame alive until the
            // draw consuming it has been submitted; never delete that texture.
            output?.release()
            input?.release()
        }
    }

    private fun ensureEngine(): BeautyEffectEngine? {
        engine?.let { return it }
        FacebetterRuntime.report("initializing")
        initializationStartedMs = SystemClock.elapsedRealtime()
        val config = BeautyEffectEngine.EngineConfig().apply {
            val credentials = FacebetterRuntime.credentials
            licenseToken = credentials.licenseToken
            appId = credentials.appId
            appKey = credentials.appKey
            externalContext = true
        }
        return BeautyEffectEngine(context, config).also { beauty ->
            engine = beauty
            val revision = credentialRevision
            val callbacks = EngineCallbacks()
            callbacks.onEngineEvent = EngineCallbacks.OnEngineEventCallback { code, _ ->
                if (!released && revision == credentialRevision) {
                    when (code) {
                        EngineEventCode.INITIALIZATION_COMPLETE -> ready = true
                        EngineEventCode.INITIALIZATION_FAILED,
                        EngineEventCode.LICENSE_VALIDATION_FAILED -> initializationFailed = true
                    }
                }
            }
            beauty.setCallbacks(callbacks)
        }
    }

    private fun applySettings(beauty: BeautyEffectEngine, settings: FacebetterSettings): Boolean {
        if (settings == applied) return true
        val codes = listOf(
            beauty.setBeautySkinOnly(true),
            beauty.setSmoothing(settings.smoothing),
            beauty.setWhitening(settings.whitening),
            beauty.setRosiness(settings.rosiness),
            beauty.setSharpening(settings.sharpening),
        )
        // -2 means asynchronous initialization has not finished yet.
        if (codes.any { it == -2 }) return false
        check(codes.all { it == 0 }) { "Facebetter basic parameters rejected: $codes" }
        val face = beauty.setReshape(Reshape.FACE_THIN, settings.faceThin)
        val eyes = beauty.setReshape(Reshape.EYE_SIZE, settings.eyeSize)
        if (face == -2 || eyes == -2) return false
        check(face in listOf(0, -3, -4) && eyes in listOf(0, -3, -4)) {
            "Facebetter reshape parameters rejected"
        }
        // Lower tiers may have no reshape capability. Continue using the
        // permitted skin effects and explicitly show this restriction in UI.
        basicOnly = (face != 0 && settings.faceThin > 0) || (eyes != 0 && settings.eyeSize > 0)
        applied = settings
        return true
    }

    private fun ensureInputTarget() {
        if (inputTexture != 0) return
        inputTexture = GlUtil.createTexture(width, height, false)
        inputFramebuffer = GlUtil.createFboForTexture(inputTexture)
    }

    private fun blit(texture: Int, transfer: Int) {
        GLES20.glDisable(GLES20.GL_BLEND)
        GLES20.glDisable(GLES20.GL_SCISSOR_TEST)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glColorMask(true, true, true, true)
        copy.use()
        copy.setSamplerTexIdUniform("uTexture", texture, 0)
        copy.setIntUniform("uTransfer", transfer)
        copy.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GlUtil.checkGlError()
    }

    private fun fail(error: Throwable) {
        failed = true
        FacebetterRuntime.report("failed")
        // Avoid logging exception messages that could contain license values.
        Log.w("Facebetter", "Beauty disabled for this GL session: ${error.javaClass.simpleName}")
    }

    private fun deleteInputTarget() {
        if (inputFramebuffer != 0) GLES20.glDeleteFramebuffers(1, intArrayOf(inputFramebuffer), 0)
        if (inputTexture != 0) GLES20.glDeleteTextures(1, intArrayOf(inputTexture), 0)
        inputFramebuffer = 0
        inputTexture = 0
    }

    override fun release() {
        released = true
        try {
            engine?.release()
        } finally {
            engine = null
            deleteInputTarget()
            try {
                copy.delete()
            } finally {
                super.release()
            }
        }
    }

    companion object {
        private const val VERTEX_SHADER = """
            attribute vec2 aPosition;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = vec4(aPosition, 0.0, 1.0);
                vTexCoord = (aPosition + 1.0) * 0.5;
            }
        """
        private const val FRAGMENT_SHADER = """
            precision highp float;
            uniform sampler2D uTexture;
            uniform int uTransfer;
            varying vec2 vTexCoord;
            vec3 encode(vec3 c) {
                return mix(12.92 * c, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0/2.4)) - 0.055,
                    step(vec3(0.0031308), c));
            }
            vec3 decode(vec3 c) {
                return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)),
                    step(vec3(0.04045), c));
            }
            void main() {
                vec4 color = texture2D(uTexture, vTexCoord);
                if (uTransfer == 1) color.rgb = encode(color.rgb);
                if (uTransfer == 2) color.rgb = decode(color.rgb);
                gl_FragColor = color;
            }
        """
    }
}
