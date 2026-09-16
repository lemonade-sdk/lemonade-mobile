import 'package:flutter/services.dart';
import 'package:isar_community/isar.dart';
import '../storage/chat_repository.dart';
import '../storage/database.dart';
import '../storage/entities/transcription_entity.dart';
import 'device_calendar_service.dart';

/// A local calendar range requested by the assistant. Calendar reads are
/// capped at 31 days so a broad prompt cannot silently pull years of events.
class DayContextRange {
  static const int maxDays = 31;

  final DateTime start;
  final DateTime end;
  final int days;

  const DayContextRange({
    required this.start,
    required this.end,
    required this.days,
  });

  factory DayContextRange.fromArgs(Map<String, dynamic> args, {DateTime? now}) {
    final localNow = now ?? DateTime.now();
    final requestedDays = (args['days'] as num?)?.toInt() ?? 1;
    if (requestedDays < 1 || requestedDays > maxDays) {
      throw ArgumentError.value(
        requestedDays,
        'days',
        'Calendar context supports 1 through $maxDays days.',
      );
    }

    final rawDate = args['start_date']?.toString().trim();
    final parsed = rawDate == null || rawDate.isEmpty
        ? null
        : DateTime.tryParse(rawDate);
    if (rawDate != null && rawDate.isNotEmpty && parsed == null) {
      throw ArgumentError.value(rawDate, 'start_date', 'Use YYYY-MM-DD.');
    }
    final source = parsed?.toLocal() ?? localNow;
    final start = DateTime(source.year, source.month, source.day);
    return DayContextRange(
      start: start,
      end: start.add(Duration(days: requestedDays)),
      days: requestedDays,
    );
  }
}

/// Collects the explicitly requested slice of personal context. Calendar
/// permission is requested by the native reader on first use. App-owned chat
/// and transcription history can be omitted with `include_app_activity=false`.
class DayContextService {
  final CalendarEventReader calendar;

  DayContextService({CalendarEventReader? calendar})
    : calendar = calendar ?? DeviceCalendarService();

  Future<String> load(Map<String, dynamic> args) async {
    final range = DayContextRange.fromArgs(args);
    final includeCalendar = args['include_calendar'] != false;
    final includeAppActivity = args['include_app_activity'] != false;
    final out = <String>[
      'DAY CONTEXT',
      'Range: ${_date(range.start)} through '
          '${_date(range.end.subtract(const Duration(days: 1)))} '
          '(${range.days} day${range.days == 1 ? '' : 's'}, local time)',
    ];

    if (includeCalendar) {
      out.add('');
      out.add('CALENDAR');
      try {
        final events = await calendar.readEvents(
          start: range.start,
          end: range.end,
        );
        if (events.isEmpty) {
          out.add('- No events found.');
        } else {
          const maxEvents = 250;
          for (final event in events.take(maxEvents)) {
            final when = event.allDay
                ? '${_date(event.start)} · all day'
                : '${_dateTime(event.start)}–${_time(event.end)}';
            final details = <String>[
              if (event.location != null) event.location!,
              if (event.calendarName != null) event.calendarName!,
            ];
            out.add(
              '- $when · ${_singleLine(event.title)}'
              '${details.isEmpty ? '' : ' · ${details.map(_singleLine).join(' · ')}'}',
            );
          }
          if (events.length > maxEvents) {
            out.add(
              '- ${events.length - maxEvents} additional events omitted.',
            );
          }
        }
      } on PlatformException catch (error) {
        if (error.code == 'calendar_permission_denied') {
          out.add(
            '- Calendar permission was not granted. The user can allow it in '
            'system Settings and ask again.',
          );
        } else {
          out.add(
            '- Calendar unavailable: ${_singleLine(error.message ?? error.code)}',
          );
        }
      } on MissingPluginException {
        out.add('- Calendar access is not supported on this platform.');
      } catch (error) {
        out.add('- Calendar unavailable: ${_singleLine(error.toString())}');
      }
    }

    if (includeAppActivity) {
      await _appendAppActivity(out, range);
    }

    return out.join('\n');
  }

  Future<void> _appendAppActivity(
    List<String> out,
    DayContextRange range,
  ) async {
    out.add('');
    out.add('LEMONADE ACTIVITY');

    try {
      final chats =
          (await ChatRepository.loadAll())
              .where(
                (chat) =>
                    !chat.lastUpdated.isBefore(range.start) &&
                    chat.lastUpdated.isBefore(range.end) &&
                    chat.messages.isNotEmpty,
              )
              .toList()
            ..sort((a, b) => a.lastUpdated.compareTo(b.lastUpdated));
      if (chats.isEmpty) {
        out.add('- Chats: none.');
      } else {
        for (final chat in chats.take(50)) {
          out.add(
            '- Chat ${_dateTime(chat.lastUpdated)} · '
            '${_singleLine(chat.displayTitle)} · ${chat.messages.length} messages',
          );
        }
        if (chats.length > 50) {
          out.add('- ${chats.length - 50} additional chats omitted.');
        }
      }
    } catch (error) {
      out.add('- Chat activity unavailable: ${_singleLine(error.toString())}');
    }

    try {
      if (!AppDatabase.isOpen) {
        out.add('- Transcriptions: unavailable.');
        return;
      }
      final rows = await AppDatabase.instance.transcriptions
          .where()
          .sortByCreatedAtDesc()
          .findAll();
      final matching =
          rows
              .where(
                (row) =>
                    !row.createdAt.isBefore(range.start) &&
                    row.createdAt.isBefore(range.end),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (matching.isEmpty) {
        out.add('- Transcriptions: none.');
      } else {
        for (final row in matching.take(30)) {
          final text = _singleLine(row.text);
          final excerpt = text.length > 240
              ? '${text.substring(0, 237)}…'
              : text;
          out.add('- Transcription ${_dateTime(row.createdAt)} · $excerpt');
        }
        if (matching.length > 30) {
          out.add(
            '- ${matching.length - 30} additional transcriptions omitted.',
          );
        }
      }
    } catch (error) {
      out.add(
        '- Transcription activity unavailable: ${_singleLine(error.toString())}',
      );
    }
  }

  static String _singleLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _date(DateTime value) =>
      '${value.year}-${_two(value.month)}-${_two(value.day)}';

  static String _time(DateTime value) =>
      '${_two(value.hour)}:${_two(value.minute)}';

  static String _dateTime(DateTime value) => '${_date(value)} ${_time(value)}';
}
