import '../types/chat_response.dart';
import '../types/tool_call.dart';

/// Accumulates indexed `delta.tool_calls[]` fragments across streaming chunks.
///
/// Per OmniRouter §6.2 / OpenAI streaming spec:
///   • First chunk for an `index` carries `id`, `type`, and `function.name`.
///   • Subsequent chunks for the same `index` carry only `function.arguments` fragments.
///   • A separate chunk carries `finish_reason`.
///
/// Use [observe] on each chunk's `delta` JSON object; [snapshot] to read in-progress
/// state for live UI; [finalize] to produce the assembled [ToolCall] list once a
/// finish chunk is seen.
class ToolCallAssembler {
  final Map<int, _Slot> _slots = {};

  /// Apply a single chunk's `delta` field. Returns the partials touched by this delta
  /// (suitable for emitting [ChatToolCallDelta]).
  List<PartialToolCall> observe(Map<String, dynamic> delta) {
    final raw = delta['tool_calls'];
    if (raw is! List) return const [];

    final touched = <PartialToolCall>[];

    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      final indexRaw = entry['index'];
      if (indexRaw is! num) continue;
      final index = indexRaw.toInt();

      final slot = _slots.putIfAbsent(index, () => _Slot(index));

      final id = entry['id'];
      if (id is String && id.isNotEmpty && slot.id == null) {
        slot.id = id;
      }

      final fn = entry['function'];
      if (fn is Map<String, dynamic>) {
        final name = fn['name'];
        if (name is String && name.isNotEmpty && slot.name == null) {
          slot.name = name;
        }
        final args = fn['arguments'];
        if (args is String && args.isNotEmpty) {
          slot.argsBuffer.write(args);
        }
      }

      touched.add(slot.toPartial());
    }

    return touched;
  }

  /// Snapshot of the current accumulator state, ordered by index.
  List<PartialToolCall> snapshot() {
    final keys = _slots.keys.toList()..sort();
    return [for (final k in keys) _slots[k]!.toPartial()];
  }

  /// Produce the final [ToolCall] list. Slots missing an `id` or `name` are dropped.
  List<ToolCall> finalize() {
    final keys = _slots.keys.toList()..sort();
    final result = <ToolCall>[];
    for (final k in keys) {
      final s = _slots[k]!;
      if (s.id == null || s.name == null) continue;
      final args = s.argsBuffer.toString();
      result.add(ToolCall(
        id: s.id!,
        name: s.name!,
        argumentsJson: args.isEmpty ? '{}' : args,
      ));
    }
    return result;
  }

  bool get isEmpty => _slots.isEmpty;
}

class _Slot {
  final int index;
  String? id;
  String? name;
  final StringBuffer argsBuffer = StringBuffer();

  _Slot(this.index);

  PartialToolCall toPartial() => PartialToolCall(
        index: index,
        id: id,
        name: name,
        argumentsAccum: argsBuffer.toString(),
      );
}
