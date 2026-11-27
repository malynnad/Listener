package com.listener.player

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * 把下载好的音频存进公共 Music 目录。
 *
 * Android 10 起分区存储禁止应用直接往 /storage/emulated/0/Music 写文件，
 * 必须先经 MediaStore 申请一条记录再写入，否则一律 Permission denied。
 * 走 MediaStore 还有个好处：系统音乐播放器与文件管理器能立刻看到。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "listener/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveAudio" -> saveAudio(
                        call.argument<String>("path"),
                        call.argument<String>("name"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveAudio(srcPath: String?, name: String?, result: MethodChannel.Result) {
        if (srcPath.isNullOrEmpty() || name.isNullOrEmpty()) {
            result.error("bad_args", "path 与 name 不能为空", null)
            return
        }
        val src = File(srcPath)
        if (!src.exists() || src.length() == 0L) {
            result.error("missing_source", "临时文件不存在或为空", null)
            return
        }
        try {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, name)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                put(MediaStore.Audio.Media.TITLE, name.substringBeforeLast('.'))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.Audio.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MUSIC + "/Listener",
                    )
                    put(MediaStore.Audio.Media.IS_PENDING, 1)
                }
            }
            val uri: Uri = contentResolver.insert(collection, values)
                ?: throw IOException("MediaStore 插入失败")
            contentResolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { input -> input.copyTo(out) }
            } ?: throw IOException("无法打开输出流")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            result.success(resolvePath(uri, name))
        } catch (e: Exception) {
            result.error("save_failed", e.message ?: "保存失败", null)
        }
    }

    /** 取回真实绝对路径，供 Dart 侧当作本地曲目使用。 */
    private fun resolvePath(uri: Uri, name: String): String {
        try {
            contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DATA),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                    if (index >= 0) {
                        val value = cursor.getString(index)
                        if (!value.isNullOrEmpty()) return value
                    }
                }
            }
        } catch (_: Exception) {
            // DATA 列在个别 ROM 上不可查，退回按约定拼路径。
        }
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "Listener",
        )
        return File(dir, name).absolutePath
    }
}
