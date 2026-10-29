import 'package:flutter_test/flutter_test.dart';
import 'package:green_farm_port/platform/host_clocks.dart';

void main() {
  test('native elapsed, awake and CPU clocks are live and monotonic', () async {
    final clocks = HostClocks.open();
    addTearDown(clocks.dispose);
    final elapsed = clocks.elapsedRealtimeMillis();
    final awake = clocks.monotonicNanos();
    final cpu = clocks.processCpuClockTicks();
    expect(elapsed, greaterThan(0));
    expect(awake, greaterThan(0));
    expect(cpu, greaterThanOrEqualTo(0));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(clocks.elapsedRealtimeMillis(), greaterThanOrEqualTo(elapsed));
    expect(clocks.monotonicNanos() - awake, greaterThanOrEqualTo(10000000));
    expect(clocks.processCpuClockTicks(), greaterThanOrEqualTo(cpu));
  });
}
