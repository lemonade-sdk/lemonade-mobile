import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/omni/tool_definitions.dart';
import 'package:lemonade_mobile/services/day_context_service.dart';
import 'package:lemonade_mobile/services/device_calendar_service.dart';

class _FakeCalendar implements CalendarEventReader {
  DateTime? requestedStart;
  DateTime? requestedEnd;

  @override
  Future<List<DeviceCalendarEvent>> readEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    requestedStart = start;
    requestedEnd = end;
    return [
      DeviceCalendarEvent(
        title: 'Project review',
        start: start.add(const Duration(hours: 10)),
        end: start.add(const Duration(hours: 11)),
        allDay: false,
        location: 'Conference room',
        calendarName: 'Work',
      ),
    ];
  }
}

void main() {
  test('device schedule tool is exposed with a 31-day schema maximum', () {
    final tool = OmniToolCatalog.byName('get_device_schedule');
    final properties = tool.parameters['properties'] as Map<String, dynamic>;
    final days = properties['days'] as Map<String, dynamic>;

    expect(tool.isAppControl, isTrue);
    expect(days['minimum'], 1);
    expect(days['maximum'], 31);
  });

  test('range accepts exactly 31 days', () {
    final range = DayContextRange.fromArgs({
      'start_date': '2026-09-01',
      'days': 31,
    });

    expect(range.start, DateTime(2026, 9, 1));
    expect(range.end, DateTime(2026, 10, 2));
  });

  test('range rejects more than 31 days', () {
    expect(() => DayContextRange.fromArgs({'days': 32}), throwsArgumentError);
  });

  test('tool result contains calendar events without app activity', () async {
    final calendar = _FakeCalendar();
    final result = await DayContextService(calendar: calendar).load({
      'start_date': '2026-09-15',
      'days': 1,
      'include_app_activity': false,
    });

    expect(calendar.requestedStart, DateTime(2026, 9, 15));
    expect(calendar.requestedEnd, DateTime(2026, 9, 16));
    expect(result, contains('Project review'));
    expect(result, contains('Conference room'));
    expect(result, isNot(contains('LEMONADE ACTIVITY')));
  });
}
