package kr.wbaseball.w_baseball

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and the app's one platform channel.
 *
 * The calendar handoff is done with `Intent.ACTION_INSERT` rather than by
 * writing to the calendar provider directly. That means:
 *  - no READ_CALENDAR / WRITE_CALENDAR permission is ever requested,
 *  - the user picks which calendar the event lands in, and
 *  - we never hold or store any of the user's calendar data.
 *
 * The iOS equivalent (EventKit's EKEventEditViewController) follows the same
 * "open a composer, let the user confirm" shape.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "kr.wbaseball.w_baseball/calendar"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
}
