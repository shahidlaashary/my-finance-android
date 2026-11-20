package com.example.my_finance

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import kotlin.math.PI
import kotlin.math.sin

class MainActivity : FlutterFragmentActivity(), TextToSpeech.OnInitListener {
    private val channelName = "my_finance/sound"
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playTone" -> {
                        val frequency = (call.argument<Number>("frequency")?.toInt() ?: 880).coerceIn(180, 1800)
                        val duration = (call.argument<Number>("durationMs")?.toInt() ?: 90).coerceIn(40, 500)
                        val volume = (call.argument<Number>("volume")?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                        Thread { playTone(frequency, duration, volume) }.start()
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text").orEmpty()
                        val language = call.argument<String>("language").orEmpty()
                        val volume = (call.argument<Number>("volume")?.toFloat() ?: 1f).coerceIn(0f, 1f)
                        if (!ttsReady || text.isBlank()) {
                            result.error("TTS_NOT_READY", "Text-to-speech is not ready on this device.", null)
                        } else {
                            val locale = when (language) {
                                "skr", "sd", "bal", "ps", "pa" -> Locale("ur")
                                else -> Locale(language.ifBlank { "en" })
                            }
                            val availability = tts?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
                            if (availability < TextToSpeech.LANG_AVAILABLE) {
                                result.error("VOICE_UNAVAILABLE", "The selected voice is not installed on this device.", null)
                            } else {
                                tts?.language = locale
                                val params = Bundle().apply {
                                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                                }
                                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "my_finance_voice")
                                result.success(true)
                            }
                        }
                    }
                    "stopSpeech" -> {
                        tts?.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playTone(frequency: Int, durationMs: Int, volume: Double) {
        val sampleRate = 22050
        val count = sampleRate * durationMs / 1000
        val samples = ShortArray(count)
        for (i in samples.indices) {
            val envelope = minOf(1.0, i / 180.0, (count - i) / 300.0).coerceAtLeast(0.0)
            val wave = sin(2.0 * PI * frequency * i / sampleRate)
            samples[i] = (wave * envelope * volume * Short.MAX_VALUE * 0.32).toInt().toShort()
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build())
            .setBufferSizeInBytes(samples.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        try {
            track.write(samples, 0, samples.size)
            track.play()
            Thread.sleep(durationMs.toLong() + 30)
        } finally {
            track.release()
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
