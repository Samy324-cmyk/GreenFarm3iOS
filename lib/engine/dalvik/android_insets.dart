import 'runtime.dart';

/// iOS supplies safe-area exclusions rather than an Android notch outline.
/// The original launcher only retains this object; the original program never
/// invokes a DisplayCutout geometry method. These are actual viewport insets.
class AndroidWindowInsetsState {
  const AndroidWindowInsetsState({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  final int left, top, right, bottom;
  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;
  DalvikObject asObject() =>
      DalvikObject('Landroid/view/WindowInsets;', nativeValue: this);
}

void registerAndroidInsets(DalvikRuntime vm) {
  vm.registerExternalClass('Landroid/view/WindowInsets;');
  vm.registerExternalClass('Landroid/view/DisplayCutout;');
  vm.registerExternalClass(
    'Landroid/view/View\$OnApplyWindowInsetsListener;',
    superclass: null,
  );
  vm.registerNative(
    'Landroid/view/WindowInsets;->getDisplayCutout()Landroid/view/DisplayCutout;',
    (_, args) {
      final insets = vm.object(args[0]).nativeValue as AndroidWindowInsetsState;
      return insets.isEmpty
          ? null
          : DalvikObject('Landroid/view/DisplayCutout;', nativeValue: insets);
    },
  );
}
