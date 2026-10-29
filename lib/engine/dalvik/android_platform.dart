import 'dart:convert';

import 'runtime.dart';

/// Platform services shared by the original Android classes and the iOS host.
/// Time sources are supplied by the host; they are never guessed from wall time.
void registerAndroidPlatform(
  DalvikRuntime vm, {
  String? model,
  String? release,
  int? compatibilitySdk,
}) {
  if (model != null || release != null || compatibilitySdk != null) {
    if (model == null || release == null || compatibilitySdk == null) {
      throw ArgumentError(
        'Model, release and compatibility SDK must be supplied together',
      );
    }
    vm.registerExternalClass('Landroid/os/Build;');
    vm
        .classes['Landroid/os/Build;']!
        .staticFields['Landroid/os/Build;->MODEL:Ljava/lang/String;'] = vm
        .newString(model);
    vm.registerExternalClass('Landroid/os/Build\$VERSION;');
    vm.classes['Landroid/os/Build\$VERSION;']!.staticFields.addAll({
      'Landroid/os/Build\$VERSION;->RELEASE:Ljava/lang/String;': vm.newString(
        release,
      ),
      'Landroid/os/Build\$VERSION;->SDK_INT:I': compatibilitySdk,
      'Landroid/os/Build\$VERSION;->SDK:Ljava/lang/String;': vm.newString(
        '$compatibilitySdk',
      ),
    });
  }
  const clock = 'Landroid/os/SystemClock;';
  vm.registerExternalClass(clock);
  vm.registerNative('$clock->elapsedRealtime()J', (_, a) {
    final source = vm.monotonicMillis;
    if (source == null) throw MissingDalvikBridge('monotonic elapsed clock');
    return source();
  });
  const log = 'Landroid/util/Log;';
  vm.registerExternalClass(log);
  for (final level in ['v', 'd', 'i', 'w', 'e', 'wtf']) {
    for (final throwable in [false, true]) {
      vm.registerNative(
        '$log->$level(Ljava/lang/String;Ljava/lang/String;${throwable ? 'Ljava/lang/Throwable;' : ''})I',
        (_, a) {
          final tag = vm.isNull(a[0]) ? 'null' : vm.string(a[0]);
          final message = vm.isNull(a[1]) ? 'null' : vm.string(a[1]);
          var text = '${level.toUpperCase()}/$tag: $message';
          if (throwable && !vm.isNull(a[2])) {
            final exception = vm.object(a[2]);
            text += '\n${exception.className}: ${exception.nativeValue ?? ''}';
            final trace = vm.throwableTraces[exception];
            if (trace != null) text += '\n${trace.join('\n')}';
          }
          vm.logDiagnostic(text);
          return utf8.encode(text).length;
        },
      );
    }
  }
}
