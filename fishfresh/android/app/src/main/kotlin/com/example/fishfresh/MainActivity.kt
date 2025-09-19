package com.example.fishfresh

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer
import org.tensorflow.lite.DataType
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "fishfresh/model"
    private var interpreter: Interpreter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initModel" -> {
                        val modelPath = call.argument<String>("path") ?: ""
                        try {
                            interpreter = Interpreter(File(assetFilePath(this, modelPath)))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("MODEL_INIT_ERROR", e.localizedMessage, null)
                        }
                    }

                    "predict" -> {
                        val imagePath = call.argument<String>("imagePath") ?: ""
                        try {
                            val bitmap = BitmapFactory.decodeFile(imagePath)

                            // 🔧 Resize to 224x224 (must match your model input)
                            val resized = Bitmap.createScaledBitmap(bitmap, 224, 224, true)

                            // 🔧 Convert to TensorImage with FLOAT32
                            val tensorImage = TensorImage(DataType.FLOAT32)
                            tensorImage.load(resized)

                            val inputBuffer = tensorImage.buffer

                            // 📝 TODO: set this to the real number of output classes
                            // Example: 3 freshness + 4 species = 7
                            val outputShape = intArrayOf(1, 7)

                            val outputBuffer = TensorBuffer.createFixedSize(
                                outputShape,
                                DataType.FLOAT32
                            )

                            interpreter?.run(inputBuffer, outputBuffer.buffer)

                            val scores = outputBuffer.floatArray.map { it.toDouble() }
                            result.success(scores)
                        } catch (e: Exception) {
                            result.error("PREDICT_ERROR", e.localizedMessage, null)
                        }
                    }

                    "disposeModel" -> {
                        interpreter?.close()
                        interpreter = null
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun assetFilePath(context: Context, assetName: String): String {
        val file = File(context.filesDir, assetName)
        if (file.exists() && file.length() > 0) {
            return file.absolutePath
        }

        context.assets.open(assetName).use { inputStream ->
            FileOutputStream(file).use { outputStream ->
                val buffer = ByteArray(4 * 1024)
                var read: Int
                while (inputStream.read(buffer).also { read = it } != -1) {
                    outputStream.write(buffer, 0, read)
                }
                outputStream.flush()
            }
        }
        return file.absolutePath
    }
}
