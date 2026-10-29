import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/ios_calendar.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';
import 'package:green_farm_port/generated/c0042.dart';

void main() {
  final oracle = jsonDecode(
    File('test/dalvik/fixtures/calendar_java_oracle.json').readAsStringSync(),
  ) as Map;
  test('316 independent Java calendar traces: DST, lenient/lazy set, locale weeks and rollover', () {
    for (final row in oracle['cases'] as List) {
      final platform = IosCalendarPlatform(
        timeZoneIdentifier: row['zone'] as String,
        firstDayOfWeek: row['first'] as int,
        minimalDaysInFirstWeek: row['minimum'] as int,
        clock: () => DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      );
      final calendar = platform.createCalendar(row['initial'] as int);
      final actual = <List<int>>[];
      for (final op in row['ops'] as List) {
        switch (op[0]) {
          case 0:
            platform.setField(calendar, op[1] as int, op[2] as int);
          case 1:
            actual.add([platform.getField(calendar, op[1] as int)]);
          case 2:
            platform.addField(calendar, op[1] as int, op[2] as int);
          case 3:
            actual.add([platform.getMillis(calendar)]);
          case 4:
            actual.add([
              for (var field = 0; field < 17; field++)
                platform.getField(calendar, field),
              platform.getMillis(calendar),
            ]);
          case 5:
            platform.setMillis(calendar, op[1] as int);
        }
      }
      expect(
        actual,
        row['expected'],
        reason:
            '${row['zone']} ${row['first']}/${row['minimum']} ${row['ops']}',
      );
      expect(
        platform.rawOffset(platform.defaultTimeZone()),
        row['rawOffset'],
        reason: '${row['zone']} raw offset',
      );
    }
  });
  test('actual device timezone ID is required and existing calendars keep their captured zone', () {
    expect(
      () => IosCalendarPlatform(
        timeZoneIdentifier: 'unknown/device',
        firstDayOfWeek: 1,
        minimalDaysInFirstWeek: 1,
        clock: () => 0,
      ),
      throwsA(isA<MissingDalvikBridge>()),
    );
    final p = IosCalendarPlatform(
      timeZoneIdentifier: 'America/New_York',
      firstDayOfWeek: 1,
      minimalDaysInFirstWeek: 1,
      clock: () => 0,
    );
    final existing = p.createCalendar(0);
    p.updateDefaults(
      timeZoneIdentifier: 'Asia/Kathmandu',
      firstDayOfWeek: 2,
      minimalDaysInFirstWeek: 4,
    );
    expect(p.getField(existing, 11), 19);
    expect(p.getField(p.createCalendar(0), 11), 5);
  });
  test(
    'Calendar natives construct Dates and preserve seconds addition across DST',
    () {
      final initial = DateTime.utc(
        2024,
        3,
        10,
        6,
        59,
        45,
      ).millisecondsSinceEpoch;
      final vm = DalvikRuntime()..wallClockMillis = () => initial;
      registerJavaCore(vm);
      registerJavaCollections(
        vm,
        calendarPlatform: IosCalendarPlatform(
          timeZoneIdentifier: 'America/New_York',
          firstDayOfWeek: 1,
          minimalDaysInFirstWeek: 1,
          clock: () => initial,
        ),
      );
      const type = 'Ljava/util/Calendar;';
      final calendar = vm.call(
        '$type->getInstance()Ljava/util/Calendar;',
        [],
        kind: 'static',
      );
      vm.call('$type->add(II)V', [calendar, 13, 30], kind: 'virtual');
      expect(vm.call('$type->get(I)I', [calendar, 11], kind: 'virtual'), 3);
      final date = vm.call('$type->getTime()Ljava/util/Date;', [
        calendar,
      ], kind: 'virtual');
      expect(
        vm.call('Ljava/util/Date;->getTime()J', [date], kind: 'virtual'),
        initial + 30000,
      );
    },
  );
  test(
    'original DEX k.z parses a timestamp through native calendar fields',
    () {
      final initial = DateTime.utc(
        2024,
        1,
        31,
        12,
        34,
        56,
        789,
      ).millisecondsSinceEpoch;
      final vm = DalvikRuntime()..wallClockMillis = () => initial;
      registerJavaCore(vm);
      registerJavaCollections(
        vm,
        calendarPlatform: IosCalendarPlatform(
          timeZoneIdentifier: 'America/New_York',
          firstDayOfWeek: 1,
          minimalDaysInFirstWeek: 1,
          clock: () => initial,
        ),
      );
      registerClass42(vm);
      const owner = 'Lc/c/a/a/a/w/k;';
      // The parser is independent of the unrelated network class initializer.
      vm.classes[owner]!.initialization = 2;
      final actual = vm.call('$owner->z(Ljava/lang/String;)J', [
        vm.newString('2024-03-10 02:30:00'),
      ], kind: 'static');
      expect(actual, DateTime.utc(2024, 3, 10, 7, 30).millisecondsSinceEpoch);
      expect(vm.executedInstructions, greaterThan(50));
    },
  );
}
