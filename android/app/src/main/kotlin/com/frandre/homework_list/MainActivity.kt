package com.frandre.homework_list

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.provider.CalendarContract.Calendars
import android.provider.CalendarContract.Events
import android.provider.CalendarContract.Reminders
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.frandre.homework_list/calendar"
        private const val PERMISSION_REQUEST_CODE = 9101
        private const val REMIND_MINUTES = 120
        private const val ACCOUNT_NAME = "学习通作业本"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensurePermission" -> requestCalendarPermission(result)
                    "addEvents" -> {
                        @Suppress("UNCHECKED_CAST")
                        val events = call.argument<List<Any?>>("events") ?: emptyList()
                        addEvents(events, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------ 权限

    private fun hasCalendarPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.WRITE_CALENDAR) ==
                PackageManager.PERMISSION_GRANTED
    }

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (hasCalendarPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "正在申请日历权限", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(
                Manifest.permission.READ_CALENDAR,
                Manifest.permission.WRITE_CALENDAR
            ),
            PERMISSION_REQUEST_CODE
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    // ------------------------------------------------------------ 写日历

    private fun addEvents(rawEvents: List<Any?>, result: MethodChannel.Result) {
        Thread {
            var added = 0
            var skipped = 0
            var failed = 0
            try {
                val calendarId = getOrCreateCalendar()
                if (calendarId <= 0) {
                    runOnUiThread {
                        result.error("no_calendar", "找不到可写入的日历", null)
                    }
                    return@Thread
                }

                for (raw in rawEvents) {
                    val event = raw as? Map<*, *> ?: continue
                    val title = event["title"] as? String ?: continue
                    val description = event["description"] as? String ?: ""
                    val start = (event["startMillis"] as? Number)?.toLong() ?: continue
                    val end = (event["endMillis"] as? Number)?.toLong()
                        ?: (start + 15 * 60 * 1000)

                    if (eventExists(calendarId, title, start)) {
                        skipped++
                        continue
                    }
                    if (insertEvent(calendarId, title, description, start, end)) {
                        added++
                    } else {
                        failed++
                    }
                }

                val payload = mapOf(
                    "added" to added,
                    "skipped" to skipped,
                    "failed" to failed
                )
                runOnUiThread { result.success(payload) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("calendar_error", e.message ?: "写入日历失败", null)
                }
            }
        }.start()
    }

    /** 优先写系统里可写的日历；没有就创建一个本地日历。 */
    private fun getOrCreateCalendar(): Long {
        val projection = arrayOf(
            Calendars._ID,
            Calendars.CALENDAR_ACCESS_LEVEL,
            Calendars.VISIBLE
        )
        contentResolver.query(
            Calendars.CONTENT_URI,
            projection,
            null,
            null,
            "${Calendars.IS_PRIMARY} DESC"
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val access = cursor.getInt(1)
                val visible = cursor.getInt(2)
                if (visible == 1 && access >= Calendars.CAL_ACCESS_CONTRIBUTOR) {
                    return id
                }
            }
        }

        val syncAdapterUri = Calendars.CONTENT_URI.buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(Calendars.ACCOUNT_NAME, ACCOUNT_NAME)
            .appendQueryParameter(
                Calendars.ACCOUNT_TYPE,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            )
            .build()

        val values = ContentValues().apply {
            put(Calendars.ACCOUNT_NAME, ACCOUNT_NAME)
            put(Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
            put(Calendars.NAME, ACCOUNT_NAME)
            put(Calendars.CALENDAR_DISPLAY_NAME, ACCOUNT_NAME)
            put(Calendars.CALENDAR_COLOR, 0xFF2E5BFF.toInt())
            put(Calendars.CALENDAR_ACCESS_LEVEL, Calendars.CAL_ACCESS_OWNER)
            put(Calendars.OWNER_ACCOUNT, ACCOUNT_NAME)
            put(Calendars.VISIBLE, 1)
            put(Calendars.SYNC_EVENTS, 1)
        }
        return contentResolver.insert(syncAdapterUri, values)
            ?.lastPathSegment?.toLongOrNull() ?: -1L
    }

    private fun eventExists(calendarId: Long, title: String, startMillis: Long): Boolean {
        val selection = "${Events.CALENDAR_ID} = ? AND ${Events.TITLE} = ? " +
                "AND ${Events.DTSTART} BETWEEN ? AND ?"
        val args = arrayOf(
            calendarId.toString(),
            title,
            (startMillis - 60_000).toString(),
            (startMillis + 60_000).toString()
        )
        contentResolver.query(
            Events.CONTENT_URI,
            arrayOf(Events._ID),
            selection,
            args,
            null
        )?.use { cursor ->
            return cursor.moveToFirst()
        }
        return false
    }

    private fun insertEvent(
        calendarId: Long,
        title: String,
        description: String,
        startMillis: Long,
        endMillis: Long
    ): Boolean {
        val values = ContentValues().apply {
            put(Events.CALENDAR_ID, calendarId)
            put(Events.TITLE, title)
            put(Events.DESCRIPTION, description)
            put(Events.DTSTART, startMillis)
            put(Events.DTEND, endMillis)
            put(Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(Events.HAS_ALARM, 1)
            put(Events.STATUS, Events.STATUS_CONFIRMED)
        }
        val uri = contentResolver.insert(Events.CONTENT_URI, values) ?: return false
        val eventId = uri.lastPathSegment?.toLongOrNull() ?: return false

        val reminder = ContentValues().apply {
            put(Reminders.EVENT_ID, eventId)
            put(Reminders.MINUTES, REMIND_MINUTES)
            put(Reminders.METHOD, Reminders.METHOD_ALERT)
        }
        contentResolver.insert(Reminders.CONTENT_URI, reminder)
        return true
    }
}
