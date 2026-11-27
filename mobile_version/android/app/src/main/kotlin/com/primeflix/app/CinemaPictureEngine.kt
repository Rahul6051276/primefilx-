package com.primeflix.app

import android.content.Context
import android.opengl.GLES20
import androidx.annotation.OptIn
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

enum class PicturePreset(
    val displayName: String,
    val tagline: String,
    val useShader: Boolean,
    val brightness: Float,
    val contrast: Float,
    val saturation: Float,
    val vibrance: Float,
    val shadowLift: Float,
    val warmth: Float,
    val sharpness: Float,
    val gamma: Float
) {
    JUST_PLAYER(
        displayName = "Just Player Pure (Default)",
        tagline = "Direct Hardware SurfaceView • True HDR10 / Natural Color",
        useShader = false,
        brightness = 0f,
        contrast = 1f,
        saturation = 1f,
        vibrance = 0f,
        shadowLift = 0f,
        warmth = 0f,
        sharpness = 0f,
        gamma = 1f
    ),
    CINEMA_NATURAL(
        displayName = "Cinema Natural",
        tagline = "Subtle clarity • Natural skin tones • Zero red tint",
        useShader = true,
        brightness = 0.01f,
        contrast = 1.06f,
        saturation = 1.06f,
        vibrance = 0.12f,
        shadowLift = 0.015f,
        warmth = 0.00f,
        sharpness = 0.18f,
        gamma = 0.97f
    ),
    BRIGHT_SDR(
        displayName = "Bright Shadow Boost",
        tagline = "Lifts dark scenes cleanly • Best for dark prints",
        useShader = true,
        brightness = 0.03f,
        contrast = 1.04f,
        saturation = 1.07f,
        vibrance = 0.14f,
        shadowLift = 0.035f,
        warmth = 0.00f,
        sharpness = 0.20f,
        gamma = 0.90f
    ),
    CRISP_4K(
        displayName = "Crisp 4K Clarity",
        tagline = "Extra edge sharpness • Cool balanced tone",
        useShader = true,
        brightness = 0.01f,
        contrast = 1.08f,
        saturation = 1.06f,
        vibrance = 0.12f,
        shadowLift = 0.01f,
        warmth = -0.03f,
        sharpness = 0.36f,
        gamma = 0.96f
    ),
    NIGHT_SOFT(
        displayName = "Night Soft",
        tagline = "Gentle eye-comfort • Balanced shadows",
        useShader = true,
        brightness = 0.00f,
        contrast = 1.02f,
        saturation = 1.02f,
        vibrance = 0.06f,
        shadowLift = 0.025f,
        warmth = 0.03f,
        sharpness = 0.12f,
        gamma = 0.95f
    )
}

object CinemaPictureEngineState {
    @Volatile
    var currentPreset: PicturePreset = PicturePreset.JUST_PLAYER
}

@OptIn(UnstableApi::class)
class CinemaPictureEffect : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram {
        return CinemaPictureShaderProgram(useHdr)
    }

    override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean = false
}

@OptIn(UnstableApi::class)
private class CinemaPictureShaderProgram(useHdr: Boolean) :
    BaseGlShaderProgram(useHdr, 1) {

    private val glProgram: GlProgram = GlProgram(VERTEX_SHADER, FRAGMENT_SHADER)
    private var texWidth = 1920
    private var texHeight = 1080

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        texWidth = inputWidth.coerceAtLeast(1)
        texHeight = inputHeight.coerceAtLeast(1)
        return Size(texWidth, texHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            val s = CinemaPictureEngineState.currentPreset

            glProgram.use()
            glProgram.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            glProgram.setBufferAttribute(
                "aFramePosition",
                GlUtil.getNormalizedCoordinateBounds(),
                GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE
            )
            glProgram.setFloatsUniform("uTransformationMatrix", GlUtil.create4x4IdentityMatrix())
            glProgram.setFloatsUniform("uTexTransformationMatrix", GlUtil.create4x4IdentityMatrix())
            glProgram.setFloatsUniform("uTexelSize", floatArrayOf(1f / texWidth, 1f / texHeight))
            glProgram.setFloatUniform("uBrightness", s.brightness)
            glProgram.setFloatUniform("uContrast", s.contrast)
            glProgram.setFloatUniform("uSaturation", s.saturation)
            glProgram.setFloatUniform("uVibrance", s.vibrance)
            glProgram.setFloatUniform("uShadowLift", s.shadowLift)
            glProgram.setFloatUniform("uWarmth", s.warmth)
            glProgram.setFloatUniform("uSharpness", s.sharpness)
            glProgram.setFloatUniform("uGamma", s.gamma.coerceIn(0.75f, 1.25f))
            glProgram.bindAttributesAndUniforms()

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            glProgram.delete()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e)
        }
    }

    companion object {
        private const val VERTEX_SHADER = """
            attribute vec4 aFramePosition;
            uniform mat4 uTransformationMatrix;
            uniform mat4 uTexTransformationMatrix;
            varying vec2 vTexSamplingCoord;
            void main() {
                gl_Position = uTransformationMatrix * aFramePosition;
                vec4 texCoord = vec4(aFramePosition.xy * 0.5 + 0.5, 0.0, 1.0);
                vTexSamplingCoord = (uTexTransformationMatrix * texCoord).xy;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uTexSampler;
            uniform vec2 uTexelSize;
            uniform float uBrightness;
            uniform float uContrast;
            uniform float uSaturation;
            uniform float uVibrance;
            uniform float uShadowLift;
            uniform float uWarmth;
            uniform float uSharpness;
            uniform float uGamma;
            varying vec2 vTexSamplingCoord;

            void main() {
                vec4 center = texture2D(uTexSampler, vTexSamplingCoord);
                vec3 color = center.rgb;

                if (uSharpness > 0.01) {
                    vec3 n = texture2D(uTexSampler, vTexSamplingCoord + vec2(0.0, uTexelSize.y)).rgb;
                    vec3 s = texture2D(uTexSampler, vTexSamplingCoord - vec2(0.0, uTexelSize.y)).rgb;
                    vec3 e = texture2D(uTexSampler, vTexSamplingCoord + vec2(uTexelSize.x, 0.0)).rgb;
                    vec3 w = texture2D(uTexSampler, vTexSamplingCoord - vec2(uTexelSize.x, 0.0)).rgb;
                    vec3 blur = (n + s + e + w) * 0.25;
                    vec3 detail = color - blur;
                    color = clamp(color + detail * (uSharpness * 0.9), 0.0, 1.0);
                }

                float lumaIn = dot(color, vec3(0.2126, 0.7152, 0.0722));
                float shadowWeight = (1.0 - lumaIn) * (1.0 - lumaIn);
                color = clamp(color + vec3(uBrightness + uShadowLift * shadowWeight), 0.0, 1.0);

                color = clamp((color - 0.5) * uContrast + 0.5, 0.0, 1.0);
                color = pow(max(color, vec3(0.0001)), vec3(uGamma));

                float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
                float maxC = max(color.r, max(color.g, color.b));
                float minC = min(color.r, min(color.g, color.b));
                float currentSat = maxC - minC;
                float vibBoost = 1.0 + uVibrance * (1.0 - clamp(currentSat, 0.0, 1.0));
                color = mix(vec3(luma), color, uSaturation * vibBoost);

                color.r += uWarmth * 0.06;
                color.b -= uWarmth * 0.06;

                gl_FragColor = vec4(clamp(color, 0.0, 1.0), center.a);
            }
        """
    }
}
