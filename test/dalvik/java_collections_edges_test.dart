import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/engine/dalvik/java_collections.dart';
import 'package:green_farm_port/engine/dalvik/java_core.dart';
import 'package:green_farm_port/engine/dalvik/numbers.dart';
import 'package:green_farm_port/engine/dalvik/runtime.dart';

void main() {
  late DalvikRuntime vm;
  setUp(() {
    vm = DalvikRuntime();
    registerJavaCore(vm);
    registerJavaCollections(vm);
  });
  Object? call(
    DalvikObject object,
    String member, [
    List<Object?> args = const [],
  ]) => vm.call('${object.className}->$member', [
    object,
    ...args,
  ], kind: 'virtual');
  DalvikObject create(String name) {
    final object = vm.allocate('Ljava/util/$name;');
    vm.call('${object.className}-><init>()V', [object], kind: 'direct');
    return object;
  }

  test('mutable custom hash keys retain stored hash and hash only once on insertion', () {
    const keyClass = 'Ltest/MutableKey;';
    vm.registerExternalClass(keyClass);
    var hashes = 0;
    vm.registerNative('$keyClass->hashCode()I', (v, a) {
      hashes++;
      return v.object(a[0]).fields['hash'];
    });
    vm.registerNative(
      '$keyClass->equals(Ljava/lang/Object;)Z',
      (v, a) => v.isNull(a[1])
          ? 0
          : v.object(a[0]).fields['id'] == v.object(a[1]).fields['id']
          ? 1
          : 0,
    );
    final key = vm.allocate(keyClass)..fields.addAll({'hash': 17, 'id': 3});
    final map = create('HashMap');
    call(map, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      key,
      vm.newString('value'),
    ]);
    expect(hashes, 1);
    key.fields['hash'] = 18;
    expect(
      call(map, 'get(Ljava/lang/Object;)Ljava/lang/Object;', [key]),
      isNull,
    );
    key.fields['hash'] = 17;
    expect(
      vm.string(call(map, 'get(Ljava/lang/Object;)Ljava/lang/Object;', [key])),
      'value',
    );
    hashes = 0;
    final set = create('HashSet');
    call(set, 'add(Ljava/lang/Object;)Z', [key]);
    expect(hashes, 1);
  });

  test('map entry views update live values and preserve Hashtable null restrictions', () {
    final table = create('Hashtable');
    call(table, 'put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;', [
      vm.newString('key'),
      vm.newString('value'),
    ]);
    final entries = call(table, 'entrySet()Ljava/util/Set;') as DalvikObject;
    final iterator =
        call(entries, 'iterator()Ljava/util/Iterator;') as DalvikObject;
    final entry = call(iterator, 'next()Ljava/lang/Object;') as DalvikObject;
    expect(
      vm.string(
        call(entry, 'setValue(Ljava/lang/Object;)Ljava/lang/Object;', [
          vm.newString('new'),
        ]),
      ),
      'value',
    );
    expect(
      vm.string(
        call(table, 'get(Ljava/lang/Object;)Ljava/lang/Object;', [
          vm.newString('key'),
        ]),
      ),
      'new',
    );
    expect(
      () =>
          call(entry, 'setValue(Ljava/lang/Object;)Ljava/lang/Object;', [null]),
      throwsA(
        isA<DalvikThrown>().having(
          (e) => e.object.className,
          'type',
          'Ljava/lang/NullPointerException;',
        ),
      ),
    );
    call(iterator, 'remove()V');
    expect(call(table, 'isEmpty()Z'), 1);
  });

  test('Calendar routes fields, epoch and timezone to supplied host', () {
    vm = DalvikRuntime()..wallClockMillis = () => 9876543210123;
    registerJavaCore(vm);
    registerJavaCollections(vm, calendarPlatform: _CalendarFixture());
    final calendar = vm.call(
      'Ljava/util/Calendar;->getInstance()Ljava/util/Calendar;',
      [],
      kind: 'static',
    ) as DalvikObject;
    call(calendar, 'set(II)V', [2, 10]);
    expect(call(calendar, 'get(I)I', [2]), 10);
    final date = call(calendar, 'getTime()Ljava/util/Date;') as DalvikObject;
    expect(call(date, 'getTime()J'), 9876543210123);
    final timezone = vm.call(
      'Ljava/util/TimeZone;->getDefault()Ljava/util/TimeZone;',
      [],
      kind: 'static',
    ) as DalvikObject;
    expect(call(timezone, 'getRawOffset()I'), -21600000);
    final wide = <Object?>[0, 0];
    JBits.setWide(wide, 0, -1234567890123);
    call(date, 'setTime(J)V', wide);
    call(calendar, 'setTime(Ljava/util/Date;)V', [date]);
    expect(
      call(
        call(calendar, 'getTime()Ljava/util/Date;') as DalvikObject,
        'getTime()J',
      ),
      -1234567890123,
    );
  });
}

/// Validates bridge routing only. This fixture is not a timezone implementation.
class _CalendarFixture implements JavaCalendarPlatform {
  @override
  Object createCalendar(int epochMillis) => <int, int>{-1: epochMillis};
  @override
  Object defaultTimeZone() => 'fixture-zone';
  @override
  int getField(Object calendar, int field) =>
      (calendar as Map<int, int>)[field]!;
  @override
  int getMillis(Object calendar) => (calendar as Map<int, int>)[-1]!;
  @override
  int rawOffset(Object timeZone) {
    expect(timeZone, 'fixture-zone');
    return -21600000;
  }

  @override
  void setField(Object calendar, int field, int value) {
    (calendar as Map<int, int>)[field] = value;
  }

  @override
  void setMillis(Object calendar, int millis) {
    (calendar as Map<int, int>)[-1] = millis;
  }
}
