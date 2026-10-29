import 'cooperative.dart';
import 'numbers.dart';
import 'runtime.dart';

class AndroidExtra {
  const AndroidExtra(this.type, this.value);
  final String type;
  final Object? value;
}

class AndroidBundleState {
  AndroidBundleState([Map<String, AndroidExtra>? values])
    : values = {...?values};
  final Map<String, AndroidExtra> values;
}

class AndroidIntentState {
  String? action, packageName, componentPackageName, className;
  DalvikObject? data, selector;
  int flags = 0;
  final Set<String> categories = {};
  AndroidBundleState? extras;
}

AndroidIntentState androidIntent(DalvikRuntime vm, Object? object) =>
    vm.object(object).nativeValue as AndroidIntentState;

DalvikObject javaAndroidIntent({
  String? action,
  String? packageName,
  String? className,
}) => DalvikObject(
  'Landroid/content/Intent;',
  nativeValue: AndroidIntentState()
    ..action = action
    ..componentPackageName = packageName
    ..className = className,
);

/// Typed Android extras and launch Intent state. Values remain VM objects and
/// raw register words; copying a Bundle copies its map, not its object values.
void registerAndroidIntents(DalvikRuntime vm) {
  const intent = 'Landroid/content/Intent;', bundle = 'Landroid/os/Bundle;';
  vm.registerExternalClass('Landroid/os/Parcelable;');
  vm.registerExternalClass(intent, interfaces: ['Landroid/os/Parcelable;']);
  vm.registerExternalClass(bundle, interfaces: ['Landroid/os/Parcelable;']);
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  String? text(Object? value) => vm.isNull(value) ? null : vm.string(value);
  DalvikObject? string(String? value) =>
      value == null ? null : vm.newString(value);
  AndroidBundleState state(Object? value) =>
      vm.object(value).nativeValue as AndroidBundleState;
  String key(Object? value) => vm.string(value);
  Object? read(
    AndroidBundleState? source,
    String name,
    String type,
    Object? fallback,
  ) {
    final found = source?.values[name];
    if (found == null) return fallback;
    if (found.type != type &&
        !(type.startsWith('L') && vm.instanceOf(found.value, type))) {
      return fallback;
    }
    return found.value;
  }

  native(bundle, '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidBundleState();
    return null;
  });
  native(bundle, '<init>($bundle)V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidBundleState(state(a[1]).values);
    return null;
  });
  native(
    bundle,
    'containsKey(Ljava/lang/String;)Z',
    (_, a) => state(a[0]).values.containsKey(key(a[1])) ? 1 : 0,
  );
  native(bundle, 'isEmpty()Z', (_, a) => state(a[0]).values.isEmpty ? 1 : 0);
  native(bundle, 'size()I', (_, a) => state(a[0]).values.length);
  native(bundle, 'clear()V', (_, a) {
    state(a[0]).values.clear();
    return null;
  });
  native(bundle, 'remove(Ljava/lang/String;)V', (_, a) {
    state(a[0]).values.remove(key(a[1]));
    return null;
  });
  native(bundle, 'putAll($bundle)V', (_, a) {
    state(a[0]).values.addAll(state(a[1]).values);
    return null;
  });
  final types = {
    'Int': 'I',
    'Long': 'J',
    'Boolean': 'Z',
    'String': 'Ljava/lang/String;',
    'Bundle': bundle,
    'Parcelable': 'Landroid/os/Parcelable;',
    'ByteArray': '[B',
    'StringArray': '[Ljava/lang/String;',
  };
  for (final entry in types.entries) {
    final type = entry.value, name = entry.key;
    native(bundle, 'put$name(Ljava/lang/String;$type)V', (_, a) {
      state(a[0]).values[key(a[1])] = AndroidExtra(
        type,
        type == 'J' ? JBits.wide(a, 2) : a[2],
      );
      return null;
    });
    final primitive = ['I', 'J', 'Z'].contains(type);
    native(
      bundle,
      'get$name(Ljava/lang/String;)$type',
      (_, a) => read(state(a[0]), key(a[1]), type, primitive ? 0 : null),
    );
    if (primitive) {
      native(
        bundle,
        'get$name(Ljava/lang/String;$type)$type',
        (_, a) => read(
          state(a[0]),
          key(a[1]),
          type,
          type == 'J' ? JBits.wide(a, 2) : a[2],
        ),
      );
    }
    native(intent, 'putExtra(Ljava/lang/String;$type)$intent', (_, a) {
      final extras = androidIntent(vm, a[0]).extras ??= AndroidBundleState();
      extras.values[key(a[1])] = AndroidExtra(
        type,
        type == 'J' ? JBits.wide(a, 2) : a[2],
      );
      return a[0];
    });
    native(
      intent,
      'get${name}Extra(Ljava/lang/String;${primitive ? type : ''})$type',
      (_, a) => read(
        androidIntent(vm, a[0]).extras,
        key(a[1]),
        type,
        primitive ? (type == 'J' ? JBits.wide(a, 2) : a[2]) : null,
      ),
    );
  }
  native(bundle, 'get(Ljava/lang/String;)Ljava/lang/Object;', (_, a) {
    final value = state(a[0]).values[key(a[1])];
    if (value == null) return null;
    final boxed = {'I': 'Integer', 'J': 'Long', 'Z': 'Boolean'}[value.type];
    if (boxed == null) return value.value;
    final words = <Object?>[value.value];
    if (value.type == 'J') {
      words.add(0);
      JBits.setWide(words, 0, value.value as int);
    }
    return vm.call(
      'Ljava/lang/$boxed;->valueOf(${value.type})Ljava/lang/$boxed;',
      words,
      kind: 'static',
    );
  });
  native(intent, '<init>()V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidIntentState();
    return null;
  });
  native(intent, '<init>(Ljava/lang/String;)V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidIntentState()..action = text(a[1]);
    return null;
  });
  native(intent, '<init>(Ljava/lang/String;Landroid/net/Uri;)V', (_, a) {
    vm.object(a[0]).nativeValue = AndroidIntentState()
      ..action = text(a[1])
      ..data = vm.isNull(a[2]) ? null : vm.object(a[2]);
    return null;
  });
  native(intent, '<init>(Landroid/content/Context;Ljava/lang/Class;)V', (_, a) {
    final descriptor = vm.object(a[2]).nativeValue as String;
    final result = AndroidIntentState()
      ..className = descriptor
          .substring(1, descriptor.length - 1)
          .replaceAll('/', '.');
    vm.object(a[0]).nativeValue = result;
    return dalvikThen(
      () => vm.call(
        'Landroid/content/Context;->getPackageName()Ljava/lang/String;',
        [a[1]],
        kind: 'virtual',
      ),
      (package) {
        result.componentPackageName = vm.string(package);
        return null;
      },
    );
  });
  native(
    intent,
    'getAction()Ljava/lang/String;',
    (_, a) => string(androidIntent(vm, a[0]).action),
  );
  native(intent, 'setAction(Ljava/lang/String;)$intent', (_, a) {
    androidIntent(vm, a[0]).action = text(a[1]);
    return a[0];
  });
  native(intent, 'setPackage(Ljava/lang/String;)$intent', (_, a) {
    androidIntent(vm, a[0]).packageName = text(a[1]);
    return a[0];
  });
  native(intent, 'getFlags()I', (_, a) => androidIntent(vm, a[0]).flags);
  native(intent, 'setFlags(I)$intent', (_, a) {
    androidIntent(vm, a[0]).flags = a[1] as int;
    return a[0];
  });
  native(intent, 'addFlags(I)$intent', (_, a) {
    androidIntent(vm, a[0]).flags |= a[1] as int;
    return a[0];
  });
  native(intent, 'addCategory(Ljava/lang/String;)$intent', (_, a) {
    androidIntent(vm, a[0]).categories.add(vm.string(a[1]));
    return a[0];
  });
  native(
    intent,
    'hasExtra(Ljava/lang/String;)Z',
    (_, a) =>
        androidIntent(vm, a[0]).extras?.values.containsKey(key(a[1])) == true
        ? 1
        : 0,
  );
  native(intent, 'getExtras()$bundle', (_, a) {
    final extras = androidIntent(vm, a[0]).extras;
    return extras == null
        ? null
        : DalvikObject(bundle, nativeValue: AndroidBundleState(extras.values));
  });
  native(intent, 'replaceExtras($intent)$intent', (_, a) {
    final source = androidIntent(vm, a[1]).extras;
    androidIntent(vm, a[0]).extras = source == null
        ? null
        : AndroidBundleState(source.values);
    return a[0];
  });
  native(intent, 'setClassName(Ljava/lang/String;Ljava/lang/String;)$intent', (
    _,
    a,
  ) {
    final value = androidIntent(vm, a[0]);
    value.componentPackageName = vm.string(a[1]);
    value.className = vm.string(a[2]);
    return a[0];
  });
  native(
    intent,
    'setClassName(Landroid/content/Context;Ljava/lang/String;)$intent',
    (_, a) => dalvikThen(
      () => vm.call(
        'Landroid/content/Context;->getPackageName()Ljava/lang/String;',
        [a[1]],
        kind: 'virtual',
      ),
      (package) {
        final value = androidIntent(vm, a[0]);
        value.componentPackageName = vm.string(package);
        value.className = vm.string(a[2]);
        return a[0];
      },
    ),
  );
  native(
    intent,
    'getData()Landroid/net/Uri;',
    (_, a) => androidIntent(vm, a[0]).data,
  );
  native(intent, 'setData(Landroid/net/Uri;)$intent', (_, a) {
    androidIntent(vm, a[0]).data = vm.isNull(a[1]) ? null : vm.object(a[1]);
    return a[0];
  });
  native(intent, 'getDataString()Ljava/lang/String;', (_, a) {
    final data = androidIntent(vm, a[0]).data;
    return data == null
        ? null
        : vm.call('Ljava/lang/Object;->toString()Ljava/lang/String;', [
            data,
          ], kind: 'virtual');
  });
  native(intent, 'setSelector($intent)V', (_, a) {
    androidIntent(vm, a[0]).selector = vm.isNull(a[1]) ? null : vm.object(a[1]);
    return null;
  });
}
