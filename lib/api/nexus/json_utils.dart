/// Shared defensive JSON coercion for Nexus DTO `fromJson` factories.
///
/// Previously each `*_models.dart` file redeclared `_str` / `_date` / `_int`
/// with small divergences (num vs string only). One set of helpers keeps
/// parsing tolerant everywhere.
library;

DateTime? jsonDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

String jsonStr(dynamic v) => v?.toString() ?? '';

int? jsonInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

int jsonIntOrZero(dynamic v) => jsonInt(v) ?? 0;

List<int> jsonIntList(dynamic v) => v is List
    ? v.map(jsonInt).whereType<int>().where((e) => e >= 0).toList()
    : const [];
