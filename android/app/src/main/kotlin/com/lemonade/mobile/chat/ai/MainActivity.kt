package com.lemonade.mobile.chat.ai

import android.Manifest
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val channelName = "ai.nexus-projects.lemonade/calendar"
    private val calendarPermissionRequest = 7401
    private var pendingCall: MethodCall? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "readEvents") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.READ_CALENDAR,
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    readEvents(call, result)
                } else {
                    pendingCall = call
                    pendingResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.READ_CALENDAR),
                        calendarPermissionRequest,
                    )
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != calendarPermissionRequest) return
        val call = pendingCall
        val result = pendingResult
        pendingCall = null
        pendingResult = null
        if (call == null || result == null) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            readEvents(call, result)
        } else {
            result.error(
                "calendar_permission_denied",
                "Calendar permission was not granted.",
                null,
            )
        }
    }

    private fun readEvents(call: MethodCall, result: MethodChannel.Result) {
        val startMillis = call.argument<Number>("startMillis")?.toLong()
        val endMillis = call.argument<Number>("endMillis")?.toLong()
        if (startMillis == null || endMillis == null || endMillis <= startMillis) {
            result.error("invalid_range", "Invalid calendar range.", null)
            return
        }

        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().apply {
            appendPath(startMillis.toString())
            appendPath(endMillis.toString())
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
        )
        val events = mutableListOf<Map<String, Any>>()
        try {
            contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { cursor ->
                val titleIndex = cursor.getColumnIndex(CalendarContract.Instances.TITLE)
                val beginIndex = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endIndex = cursor.getColumnIndex(CalendarContract.Instances.END)
                val allDayIndex = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)
                val locationIndex = cursor.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
                val calendarIndex = cursor.getColumnIndex(
                    CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
                )
                val utcDate = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val localDate = SimpleDateFormat("yyyy-MM-dd", Locale.US)
                val requestedStartDate = localDate.format(Date(startMillis))
                val requestedEndDate = localDate.format(Date(endMillis))
                while (cursor.moveToNext()) {
                    val begin = cursor.getLong(beginIndex)
                    val end = cursor.getLong(endIndex)
                    val allDay = cursor.getInt(allDayIndex) == 1
                    val allDayDate = if (allDay) utcDate.format(Date(begin)) else ""
                    if (allDay && (utcDate.format(Date(end)) <= requestedStartDate ||
                                allDayDate >= requestedEndDate)) {
                        continue
                    }
                    events.add(
                        mapOf(
                            "title" to (cursor.getString(titleIndex) ?: "(Untitled event)"),
                            "startMillis" to begin,
                            "endMillis" to end,
                            "allDay" to allDay,
                            "allDayDate" to allDayDate,
                            "location" to (cursor.getString(locationIndex) ?: ""),
                            "calendarName" to (cursor.getString(calendarIndex) ?: ""),
                        ),
                    )
                }
            }
            result.success(events)
        } catch (error: Exception) {
            result.error("calendar_read_failed", error.localizedMessage, null)
        }
    }
}
