import 'package:flutter/services.dart';

/// Read-only calendar event used for assistant context. Notes, attendees, and
/// event identifiers are intentionally omitted so the model receives only the
/// information needed to summarize a schedule.
class DeviceCalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? calendarName;

  const DeviceCalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.calendarName,
  });

  factory DeviceCalendarEvent.fromMap(Map<Object?, Object?> map) {
    final startMillis = (map['startMillis'] as num?)?.toInt() ?? 0;
    final endMillis = (map['endMillis'] as num?)?.toInt() ?? startMillis;
    String? optionalString(Object? value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return DeviceCalendarEvent(
      title: optionalString(map['title']) ?? '(Untitled event)',
      start: DateTime.fromMillisecondsSinceEpoch(startMillis),
      end: DateTime.fromMillisecondsSinceEpoch(endMillis),
      allDay: map['allDay'] == true || map['allDay'] == 1,
      location: optionalString(map['location']),
      calendarName: optionalString(map['calendarName']),
    );
  }
}

abstract class CalendarEventReader {
  Future<List<DeviceCalendarEvent>> readEvents({
    required DateTime start,
    required DateTime end,
  });
}

/// Native EventKit / Android Calendar Provider bridge.
///
/// The native side asks for read access on first use. It never creates,
/// modifies, or deletes an event.
class DeviceCalendarService implements CalendarEventReader {
  static const MethodChannel _channel = MethodChannel(
    'ai.nexus-projects.lemonade/calendar',
  );

  @override
  Future<List<DeviceCalendarEvent>> readEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    final raw = await _channel.invokeListMethod<Object?>('readEvents', {
      'startMillis': start.millisecondsSinceEpoch,
      'endMillis': end.millisecondsSinceEpoch,
    });
    if (raw == null) return const [];
    final events = <DeviceCalendarEvent>[];
    for (final value in raw) {
      if (value is Map) {
        events.add(DeviceCalendarEvent.fromMap(value.cast<Object?, Object?>()));
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }
}
