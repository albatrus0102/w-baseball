package kr.wbaseball.w_baseball

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Hosts the Flutter UI and the app's platform channels.
 *
 * The calendar handoff is done with `Intent.ACTION_INSERT` rather than by
 * writing to the calendar provider directly. That means:
 *  - no READ_CALENDAR / WRITE_CALENDAR permission is ever requested,
 *  - the user picks which calendar the event lands in, and
 *  - we never hold or store any of the user's calendar data.
 *
 * The iOS equivalent (EventKit's EKEventEditViewController) follows the same
 * "open a composer, let the user confirm" shape.
 *
 * 출전 일지 가져오기's file picker follows the identical shape: `ACTION_OPEN_
 * DOCUMENT` (Storage Access Framework) rather than a plugin dependency or a
 * direct filesystem read, so:
 *  - no storage permission is ever requested (see `docs/privacy-policy.md`'s
 *    permission table — this feature adds no row to it),
 *  - the user explicitly picks the one file we get to read, and
 *  - we hold no lasting access to anything else on the device.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CALENDAR_CHANNEL = "kr.wbaseball.w_baseball/calendar"
        const val FILE_OPEN_CHANNEL = "kr.wbaseball.w_baseball/file_open"
        const val REQUEST_OPEN_FILE = 4201
    }

    // The `MethodChannel.Result` for an in-flight "openTextFile" call. Held
    // here rather than returned synchronously: `startActivityForResult`
    // returns control to Android immediately, and the real answer only
    // arrives later in `onActivityResult`, on a different callback entirely.
    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingMaxBytes: Int = 5 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "insertEvent" -> result.success(insertEvent(call.argument("title"),
                        call.argument("beginTime"),
                        call.argument("endTime"),
                        call.argument("location"),
                        call.argument("description")))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_OPEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTextFile" -> openTextFile(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun insertEvent(
        title: String?,
        beginTime: Long?,
        endTime: Long?,
        location: String?,
        description: String?,
    ): Boolean {
        if (title == null || beginTime == null || endTime == null) return false

        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title)
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginTime)
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime)
            location?.let { putExtra(CalendarContract.Events.EVENT_LOCATION, it) }
            description?.let { putExtra(CalendarContract.Events.DESCRIPTION, it) }
        }

        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            // No calendar app installed. Reported back so Flutter can show a
            // real message instead of appearing to do nothing.
            false
        }
    }

    private fun openTextFile(call: MethodCall, result: MethodChannel.Result) {
        if (pendingFileResult != null) {
            // A picker is already open for an earlier call — refuse the new
            // one rather than losing track of which caller gets the answer.
            result.error("busy", "이미 파일 선택 창이 열려 있습니다.", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val mimeTypes = (call.argument<List<String>>("mimeTypes") ?: listOf("*/*"))
        pendingMaxBytes = call.argument<Int>("maxBytes") ?: (5 * 1024 * 1024)
        pendingFileResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeTypes.firstOrNull() ?: "*/*"
            if (mimeTypes.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
        }

        try {
            startActivityForResult(intent, REQUEST_OPEN_FILE)
        } catch (e: ActivityNotFoundException) {
            pendingFileResult = null
            result.error("no_picker", "파일 선택 앱을 찾을 수 없습니다.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_OPEN_FILE) return
        val result = pendingFileResult ?: return
        pendingFileResult = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null) // The user picked nothing.
            return
        }

        try {
            val bytes = contentResolver.openInputStream(uri)?.use { stream ->
                readLimited(stream, pendingMaxBytes)
            }
            if (bytes == null) {
                result.error("read_failed", "파일을 열 수 없습니다.", null)
                return
            }
            if (bytes.size > pendingMaxBytes) {
                result.error("file_too_large", "파일이 너무 큽니다.", null)
                return
            }
            result.success(
                mapOf(
                    "content" to String(bytes, Charsets.UTF_8),
                    "fileName" to queryDisplayName(uri),
                )
            )
        } catch (e: Exception) {
            result.error("read_failed", "파일을 읽을 수 없습니다.", null)
        }
    }

    /** Reads at most `limit + 1` bytes, so the caller can detect "over limit"
     * without first buffering an unbounded file fully into memory. */
    private fun readLimited(stream: java.io.InputStream, limit: Int): ByteArray {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        while (buffer.size() <= limit) {
            val n = stream.read(chunk)
            if (n < 0) break
            buffer.write(chunk, 0, n)
        }
        return buffer.toByteArray()
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            }
    }
}
