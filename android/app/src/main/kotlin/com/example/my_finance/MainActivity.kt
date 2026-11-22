package com.example.my_finance

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Bundle
import android.os.StatFs
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.sin

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "my_finance/sound"
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStorageInfo" -> try {
                    val stats = StatFs(filesDir.absolutePath)
                    result.success(mapOf("totalBytes" to stats.totalBytes, "freeBytes" to stats.availableBytes))
                } catch (error: Exception) {
                    result.error("STORAGE_UNAVAILABLE", "Device storage information is unavailable.", null)
                }
                "playPattern" -> {
                    val steps = call.argument<List<Map<String, Any>>>("pattern").orEmpty().take(8)
                    val volume = (call.argument<Number>("volume")?.toDouble() ?: 0.5).coerceIn(0.0, 1.0)
                    Thread {
                        steps.forEach { step ->
                            val frequency = ((step["frequency"] as? Number)?.toInt() ?: 880).coerceIn(180, 1800)
                            val duration = ((step["durationMs"] as? Number)?.toInt() ?: 90).coerceIn(40, 500)
                            val waveform = step["waveform"]?.toString() ?: "soft"
                            playTone(frequency, duration, volume, waveform)
                            Thread.sleep(35)
                        }
                    }.start()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playTone(frequency: Int, durationMs: Int, volume: Double, waveform: String) {
        val sampleRate = 22050
        val count = sampleRate * durationMs / 1000
        val samples = ShortArray(count)
        for (i in samples.indices) {
            val envelope = minOf(1.0, i / 180.0, (count - i) / 300.0).coerceAtLeast(0.0)
            val phase = 2.0 * PI * frequency * i / sampleRate
            val fundamental = sin(phase)
            val wave = when (waveform) {
                "bell" -> fundamental * 0.72 + sin(phase * 2.01) * 0.20 + sin(phase * 3.97) * 0.08
                "pluck" -> fundamental * 0.78 + sin(phase * 2.0) * 0.22
                "bright" -> fundamental * 0.62 + sin(phase * 2.0) * 0.27 + sin(phase * 3.0) * 0.11
                "warm" -> fundamental * 0.84 + sin(phase * 1.5) * 0.16
                else -> fundamental
            }
            samples[i] = (wave * envelope * volume * Short.MAX_VALUE * 0.32).toInt().toShort()
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(samples.size * 2).setTransferMode(AudioTrack.MODE_STATIC).build()
        try {
            track.write(samples, 0, samples.size)
            track.play()
            Thread.sleep(durationMs.toLong() + 30)
        } finally {
            track.release()
        }
    }
}
