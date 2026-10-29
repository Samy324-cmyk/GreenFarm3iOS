import 'dart:typed_data';

import 'android_intents.dart';
import 'runtime.dart';

class AndroidPackageEnvironment {
  AndroidPackageEnvironment({
    required this.manifest,
    required this.dataDirectory,
    required this.resourceId,
    required this.resourceValue,
    this.sourceArchivePath,
    this.signingCertificates,
  });
  final Map<String, dynamic> manifest;
  final String dataDirectory;
  final String? sourceArchivePath;
  final List<List<int>>? signingCertificates;
  final int Function(String reference) resourceId;
  final Object? Function(String reference) resourceValue;
}

/// Metadata for the supplied, retained APK. Other installed packages and OS
/// identities require separate host integration and are not invented here.
void registerAndroidPackages(
  DalvikRuntime vm, {
  required AndroidPackageEnvironment environment,
}) {
  const manager = 'Landroid/content/pm/PackageManager;',
      item = 'Landroid/content/pm/PackageItemInfo;',
      app = 'Landroid/content/pm/ApplicationInfo;',
      package = 'Landroid/content/pm/PackageInfo;',
      activity = 'Landroid/content/pm/ActivityInfo;',
      signature = 'Landroid/content/pm/Signature;';
  vm.registerExternalClass(manager);
  vm.registerExternalClass(item);
  vm.registerExternalClass(app, superclass: item);
  vm.registerExternalClass(package);
  vm.registerExternalClass(activity, superclass: item);
  vm.registerExternalClass(signature);
  vm.registerExternalClass(
    'Landroid/content/pm/PackageManager\$NameNotFoundException;',
    superclass: 'Ljava/lang/Exception;',
  );
  void fields(String owner, Map<String, String> names) {
    for (final field in names.entries) {
      vm.classes[owner]!.instanceFields['$owner->${field.key}:${field.value}'] =
          field.value;
    }
  }

  fields(item, {
    'name': 'Ljava/lang/String;',
    'packageName': 'Ljava/lang/String;',
    'labelRes': 'I',
    'icon': 'I',
    'metaData': 'Landroid/os/Bundle;',
  });
  fields(app, {
    'sourceDir': 'Ljava/lang/String;',
    'publicSourceDir': 'Ljava/lang/String;',
    'dataDir': 'Ljava/lang/String;',
    'className': 'Ljava/lang/String;',
    'minSdkVersion': 'I',
    'targetSdkVersion': 'I',
  });
  fields(package, {
    'packageName': 'Ljava/lang/String;',
    'versionName': 'Ljava/lang/String;',
    'versionCode': 'I',
    'applicationInfo': app,
    'requestedPermissions': '[Ljava/lang/String;',
    'activities': '[$activity',
    'signatures': '[$signature',
  });
  fields(activity, {'applicationInfo': app});
  void native(String owner, String member, DalvikBody body) =>
      vm.registerNative('$owner->$member', body);
  final manifest = environment.manifest,
      ownPackage = environment.manifest['package'] as String;
  void own(String name) {
    if (name != ownPackage) {
      throw MissingDalvikBridge('Installed host package metadata: $name');
    }
  }

  String fullName(String name) => name.startsWith('.')
      ? '$ownPackage$name'
      : name.contains('.')
      ? name
      : '$ownPackage.$name';
  AndroidExtra extra(Object? value) {
    if (value is bool) return AndroidExtra('Z', value ? 1 : 0);
    if (value is int) return AndroidExtra('I', value);
    if (value is double) {
      return AndroidExtra(
        'F',
        (ByteData(
          4,
        )..setFloat32(0, value, Endian.little)).getInt32(0, Endian.little),
      );
    }
    return AndroidExtra('Ljava/lang/String;', vm.newString(value as String));
  }

  DalvikObject metadata() {
    final values = <String, AndroidExtra>{};
    for (final raw in (manifest['applicationMetadata'] as List? ?? [])) {
      final entry = raw as Map, name = entry['name'] as String;
      if (entry['resource'] != null) {
        values[name] = AndroidExtra(
          'I',
          environment.resourceId(entry['resource'] as String),
        );
        continue;
      }
      final text = entry['value'] as String;
      Object? value;
      if (text.startsWith('@')) {
        value = environment.resourceValue(text);
        if (value == null) {
          throw MissingDalvikBridge('Manifest metadata resource $text');
        }
      } else if (text == 'true' || text == 'false') {
        value = text == 'true';
      } else {
        value = int.tryParse(text) ?? double.tryParse(text) ?? text;
      }
      values[name] = extra(value);
    }
    return DalvikObject(
      'Landroid/os/Bundle;',
      nativeValue: AndroidBundleState(values),
    );
  }

  DalvikObject application(int flags) {
    final path = environment.sourceArchivePath;
    if (path == null) {
      throw MissingDalvikBridge('Original APK source archive path');
    }
    final attributes = manifest['applicationAttributes'] as Map? ?? {};
    final value = vm.allocate(app);
    value.fields.addAll({
      '$item->packageName:Ljava/lang/String;': vm.newString(ownPackage),
      '$item->name:Ljava/lang/String;': attributes['name'] == null
          ? null
          : vm.newString(fullName(attributes['name'] as String)),
      '$item->labelRes:I': attributes['label'] == null
          ? 0
          : environment.resourceId(attributes['label'] as String),
      '$item->icon:I': attributes['icon'] == null
          ? 0
          : environment.resourceId(attributes['icon'] as String),
      '$item->metaData:Landroid/os/Bundle;': flags & 128 != 0
          ? metadata()
          : null,
      '$app->sourceDir:Ljava/lang/String;': vm.newString(path),
      '$app->publicSourceDir:Ljava/lang/String;': vm.newString(path),
      '$app->dataDir:Ljava/lang/String;': vm.newString(
        environment.dataDirectory,
      ),
      '$app->className:Ljava/lang/String;': attributes['name'] == null
          ? null
          : vm.newString(fullName(attributes['name'] as String)),
      '$app->minSdkVersion:I': manifest['minSdk'],
      '$app->targetSdkVersion:I': manifest['targetSdk'],
    });
    return value;
  }

  final object = DalvikObject(manager, nativeValue: environment);
  native(
    'Landroid/content/Context;',
    'getPackageManager()$manager',
    (_, a) => object,
  );
  native(
    'Landroid/content/Context;',
    'getApplicationInfo()$app',
    (_, a) => application(0),
  );
  native(manager, 'getApplicationInfo(Ljava/lang/String;I)$app', (_, a) {
    own(vm.string(a[1]));
    return application(a[2] as int);
  });
  native(manager, 'getPackageInfo(Ljava/lang/String;I)$package', (_, a) {
    own(vm.string(a[1]));
    final flags = a[2] as int,
        value = vm.allocate(package),
        appInfo = application(flags);
    value.fields.addAll({
      '$package->packageName:Ljava/lang/String;': vm.newString(ownPackage),
      '$package->versionName:Ljava/lang/String;': vm.newString(
        manifest['versionName'] as String,
      ),
      '$package->versionCode:I': manifest['versionCode'],
      '$package->applicationInfo:$app': appInfo,
    });
    if (flags & 4096 != 0) {
      final names = manifest['requestedPermissions'] as List? ?? [];
      value.fields['$package->requestedPermissions:[Ljava/lang/String;'] =
          vm.array('[Ljava/lang/String;', names.length)
            ..values.setAll(
              0,
              names.map((name) => vm.newString(name as String)),
            );
    }
    if (flags & 1 != 0) {
      final entries = manifest['activities'] as List? ?? [];
      final values = vm.array('[$activity', entries.length);
      for (var index = 0; index < entries.length; index++) {
        final info = vm.allocate(activity), entry = entries[index] as Map;
        info.fields.addAll({
          '$item->name:Ljava/lang/String;': vm.newString(
            fullName(entry['name'] as String),
          ),
          '$item->packageName:Ljava/lang/String;': vm.newString(ownPackage),
          '$activity->applicationInfo:$app': appInfo,
        });
        values.values[index] = info;
      }
      value.fields['$package->activities:[$activity'] = values;
    }
    if (flags & 64 != 0) {
      final certs = environment.signingCertificates;
      if (certs == null) {
        throw MissingDalvikBridge('Actual APK signing certificates');
      }
      value.fields['$package->signatures:[$signature'] =
          vm.array('[$signature', certs.length)
            ..values.setAll(
              0,
              certs.map(
                (bytes) => DalvikObject(
                  signature,
                  nativeValue: Uint8List.fromList(bytes),
                ),
              ),
            );
    }
    return value;
  });
  native(signature, 'toByteArray()[B', (_, a) {
    final data = vm.object(a[0]).nativeValue as Uint8List;
    return vm.array('[B', data.length)
      ..values.setAll(0, data.map((v) => v.toSigned(8)));
  });
  native(
    signature,
    'toCharsString()Ljava/lang/String;',
    (_, a) => vm.newString(
      (vm.object(a[0]).nativeValue as Uint8List)
          .map((v) => v.toRadixString(16).padLeft(2, '0'))
          .join(),
    ),
  );
  native(signature, 'hashCode()I', (_, a) {
    var hash = 1;
    for (final byte in vm.object(a[0]).nativeValue as Uint8List) {
      hash = (31 * hash + byte.toSigned(8)).toSigned(32);
    }
    return hash;
  });
  native(signature, 'equals(Ljava/lang/Object;)Z', (_, a) {
    if (vm.isNull(a[1]) || !vm.instanceOf(a[1], signature)) return 0;
    final left = vm.object(a[0]).nativeValue as Uint8List,
        right = vm.object(a[1]).nativeValue as Uint8List;
    if (left.length != right.length) return 0;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return 0;
    }
    return 1;
  });
}
