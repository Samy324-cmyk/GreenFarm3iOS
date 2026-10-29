import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'java_collections.dart';
import 'runtime.dart';

const _day = 86400000;

/// Original Android Calendar.getInstance() constructs GregorianCalendar.
/// IANA 2026e supplies transitions; the timezone ID and locale week rules must
/// be supplied by GreenFarmHost.information(). Unknown IDs never become UTC.
class IosCalendarPlatform
    implements JavaCalendarPlatform, JavaCalendarArithmetic {
  IosCalendarPlatform({
    required String timeZoneIdentifier,
    required int firstDayOfWeek,
    required int minimalDaysInFirstWeek,
    required this.clock,
  }) {
    if (!_initialized) {
      tzdata.initializeTimeZones();
      _initialized = true;
    }
    updateDefaults(
      timeZoneIdentifier: timeZoneIdentifier,
      firstDayOfWeek: firstDayOfWeek,
      minimalDaysInFirstWeek: minimalDaysInFirstWeek,
    );
  }
  static bool _initialized = false;
  static const databaseVersion = '2026e';
  final int Function() clock;
  late tz.Location _location;
  late int _firstDay, _minimalDays;

  /// Call after refreshing host information on a locale/timezone change.
  /// Existing calendars retain the defaults they captured at construction.
  void updateDefaults({
    required String timeZoneIdentifier,
    required int firstDayOfWeek,
    required int minimalDaysInFirstWeek,
  }) {
    if (firstDayOfWeek < 1 ||
        firstDayOfWeek > 7 ||
        minimalDaysInFirstWeek < 1 ||
        minimalDaysInFirstWeek > 7) {
      throw ArgumentError('Invalid native Gregorian week rules');
    }
    try {
      _location = tz.getLocation(timeZoneIdentifier);
    } on tz.LocationNotFoundException {
      throw MissingDalvikBridge(
        'IANA timezone $timeZoneIdentifier is absent from $databaseVersion',
      );
    }
    _firstDay = firstDayOfWeek;
    _minimalDays = minimalDaysInFirstWeek;
  }

  @override
  Object createCalendar(int epochMillis) =>
      _Calendar(_location, _firstDay, _minimalDays, epochMillis);
  @override
  int getField(Object calendar, int field) =>
      (calendar as _Calendar).get(field);
  @override
  void setField(Object calendar, int field, int value) =>
      (calendar as _Calendar).set(field, value);
  @override
  int getMillis(Object calendar) => (calendar as _Calendar).resolve();
  @override
  void setMillis(Object calendar, int millis) =>
      (calendar as _Calendar).setMillis(millis);
  @override
  void addField(Object calendar, int field, int amount) =>
      (calendar as _Calendar).add(field, amount);
  @override
  Object defaultTimeZone() => _location;
  @override
  int rawOffset(Object timeZone) =>
      _standardOffset(timeZone as tz.Location, clock());
}

int _offset(tz.Location location, int instant) =>
    location.timeZone(instant).offset.inMilliseconds;

int _standardOffset(tz.Location location, int instant) {
  final here = location.lookupTimeZone(instant);
  if (!here.timeZone.isDst) return here.timeZone.offset.inMilliseconds;
  // Rearguard IANA data describes standard/DST offsets with Java conventions.
  // Find the nearest actual standard-time interval, rather than assuming DST
  // is one hour (Lord Howe is 30 minutes; historical changes also differ).
  int? distance, result;
  for (var i = 0; i < location.transitionAt.length; i++) {
    final zone = location.zones[location.transitionZone[i]];
    if (zone.isDst) continue;
    final start = location.transitionAt[i];
    final end = i + 1 < location.transitionAt.length
        ? location.transitionAt[i + 1]
        : 8640000000000000;
    final d = instant < start
        ? start - instant
        : instant >= end
        ? instant - end
        : 0;
    if (distance == null || d < distance) {
      distance = d;
      result = zone.offset.inMilliseconds;
    }
  }
  if (result != null) return result;
  throw MissingDalvikBridge(
    'No standard timezone interval for ${location.name} at $instant',
  );
}

class _Calendar {
  _Calendar(this.location, this.firstDay, this.minimalDays, int instant) {
    setMillis(instant);
  }
  final tz.Location location;
  final int firstDay, minimalDays;
  int millis = 0;
  final List<int> fields = List.filled(17, 0);
  final List<int> stamps = List.filled(17, 1);
  int nextStamp = 2;
  bool dirty = false;

  static Never _range() => throw MissingDalvikBridge(
    'GregorianCalendar before the 1582 cutover or outside Dart date range',
  );
  DateTime local(int value) {
    DateTime date;
    try {
      date = DateTime.fromMillisecondsSinceEpoch(
        value + _offset(location, value),
        isUtc: true,
      );
    } on ArgumentError {
      _range();
    }
    if (date.year < 1583) _range();
    return date;
  }

  void setMillis(int value) {
    millis = value;
    dirty = false;
    _populate();
  }

  int _weekStart(int year, int month) {
    final start = DateTime.utc(year, month);
    final dow = start.weekday % 7 + 1;
    final preceding = (dow - firstDay) % 7;
    return start.millisecondsSinceEpoch -
        preceding * _day +
        (7 - preceding < minimalDays ? 7 * _day : 0);
  }

  void _populate() {
    final d = local(millis);
    final midnight = DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).millisecondsSinceEpoch;
    final jan1 = DateTime.utc(d.year).millisecondsSinceEpoch;
    var weekStart = _weekStart(d.year, 1);
    if (midnight < weekStart) {
      weekStart = _weekStart(d.year - 1, 1);
    } else if (midnight >= _weekStart(d.year + 1, 1)) {
      weekStart = _weekStart(d.year + 1, 1);
    }
    final standard = _standardOffset(location, millis);
    fields.setAll(0, [
      1,
      d.year,
      d.month - 1,
      (midnight - weekStart) ~/ (7 * _day) + 1,
      ((midnight - _weekStart(d.year, d.month)) / (7 * _day)).floor() + 1,
      d.day,
      (midnight - jan1) ~/ _day + 1,
      d.weekday % 7 + 1,
      (d.day - 1) ~/ 7 + 1,
      d.hour ~/ 12,
      d.hour % 12,
      d.hour,
      d.minute,
      d.second,
      d.millisecond,
      standard,
      _offset(location, millis) - standard,
    ]);
    stamps.fillRange(0, 17, 1);
    nextStamp = 2;
  }

  int get(int field) {
    if (field < 0 || field >= 17) {
      throw RangeError.range(field, 0, 16, 'Calendar field');
    }
    resolve();
    return fields[field];
  }

  void set(int field, int value) {
    // These are all date/time fields written by the recovered APK. Other
    // field groups need Calendar's separate stamp-resolution algorithms.
    if (!const {1, 2, 5, 9, 10, 11, 12, 13, 14}.contains(field)) {
      throw MissingDalvikBridge('Calendar.set field $field');
    }
    fields[field] = value;
    stamps[field] = nextStamp++;
    dirty = true;
  }

  int resolve() {
    if (!dirty) return millis;
    final hour = stamps[11] >= (stamps[9] > stamps[10] ? stamps[9] : stamps[10])
        ? fields[11]
        : fields[10] + 12 * fields[9];
    DateTime normalized;
    try {
      normalized = DateTime.utc(
        fields[1],
        fields[2] + 1,
        fields[5],
        hour,
        fields[12],
        fields[13],
        fields[14],
      );
    } on ArgumentError {
      _range();
    }
    if (normalized.year < 1583) _range();
    millis = _resolveWall(normalized.millisecondsSinceEpoch);
    dirty = false;
    _populate();
    return millis;
  }

  int _resolveWall(int wall) {
    int? latest;
    for (final offset
        in location.zones.map((z) => z.offset.inMilliseconds).toSet()) {
      final candidate = wall - offset;
      if (_offset(location, candidate) == offset &&
          (latest == null || candidate > latest)) {
        latest = candidate;
      }
    }
    // Java chooses the later (normally standard-time) occurrence at overlap.
    if (latest != null) return latest;
    for (final transition in location.transitionAt) {
      if (transition < wall - 2 * _day || transition > wall + 2 * _day) {
        continue;
      }
      final before = _offset(location, transition - 1),
          after = _offset(location, transition);
      if (after > before &&
          wall >= transition + before &&
          wall < transition + after) {
        // Lenient Java Calendar moves a nonexistent wall time forward by the
        // real gap width, preserving minutes/seconds/milliseconds.
        return wall - before;
      }
    }
    throw MissingDalvikBridge(
      'Cannot resolve local time $wall in ${location.name}',
    );
  }

  void add(int field, int amount) {
    if (amount == 0) return;
    resolve();
    final multiplier = switch (field) {
      10 || 11 => 3600000,
      12 => 60000,
      13 => 1000,
      14 => 1,
      _ => null,
    };
    if (multiplier != null) {
      setMillis(millis + multiplier * amount);
      return;
    }
    if (field == 1 || field == 2) {
      final year = fields[1] + (field == 1 ? amount : 0);
      final month = fields[2] + 1 + (field == 2 ? amount : 0);
      final target = DateTime.utc(year, month);
      final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
      fields[1] = target.year;
      fields[2] = target.month - 1;
      if (fields[5] > lastDay) fields[5] = lastDay;
      dirty = true;
      resolve();
      return;
    }
    if (const {3, 4, 5, 6, 7, 8}.contains(field)) {
      final days = const {3, 4, 8}.contains(field) ? amount * 7 : amount;
      final target = DateTime.utc(
        fields[1],
        fields[2] + 1,
        fields[5] + days,
        fields[11],
        fields[12],
        fields[13],
        fields[14],
      );
      final oldOffset = _offset(location, millis);
      var candidate = target.millisecondsSinceEpoch - oldOffset;
      final adjusted = candidate + oldOffset - _offset(location, candidate);
      final adjustedDate = local(adjusted);
      // GregorianCalendar.add retains the previous offset in an overlap.
      // Across a gap it applies the offset correction only if the intended
      // local date remains intact; this also handles Apia's omitted day.
      if (adjustedDate.year == target.year &&
          adjustedDate.month == target.month &&
          adjustedDate.day == target.day) {
        candidate = adjusted;
      }
      setMillis(candidate);
      return;
    }
    throw MissingDalvikBridge('Calendar.add field $field');
  }
}
