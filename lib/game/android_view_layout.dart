import 'dart:math' as math;
import 'dart:ui';

import '../engine/dalvik/android_context.dart';
import '../engine/dalvik/runtime.dart';

/// Measures the original launcher's MATCH_PARENT tree against the actual
/// Flutter viewport. Unsupported content measurement fails rather than giving
/// zero dimensions to the original screen/asset selector.
class AndroidViewLayout {
  AndroidViewLayout(this.vm, this.environment);
  final DalvikRuntime vm;
  final AndroidContextEnvironment environment;
  final Map<AndroidViewState, Rect> bounds = Map.identity();
  static const _params = 'Landroid/view/ViewGroup\$LayoutParams;';
  static const _margins = 'Landroid/view/ViewGroup\$MarginLayoutParams;';

  void layout(AndroidViewState root, int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Viewport must be laid out');
    }
    bounds.clear();
    _place(
      root,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      isRoot: true,
    );
  }

  void _place(AndroidViewState view, Rect available, {bool isRoot = false}) {
    if (view.visibility == 8) {
      view.width = view.height = 0;
      bounds[view] = Rect.fromLTWH(available.left, available.top, 0, 0);
      return;
    }
    final params = view.layoutParams;
    int value(String key) =>
        params == null ? 0 : vm.getField(params, key) as int;
    int margin(String side) => params != null && vm.instanceOf(params, _margins)
        ? value('$_margins->${side}Margin:I')
        : 0;
    final left = margin('left'), top = margin('top');
    final right = margin('right'), bottom = margin('bottom');
    int measure(String axis, double maximum) {
      final requested = isRoot || params == null
          ? -1
          : value('$_params->$axis:I');
      if (requested == -2) {
        throw MissingDalvikBridge(
          'Wrap-content measurement for ${view.object.className}',
        );
      }
      return requested == -1
          ? math.max(0, maximum.floor())
          : math.max(0, requested);
    }

    view.width = measure('width', available.width - left - right);
    view.height = measure('height', available.height - top - bottom);
    final rectangle = Rect.fromLTWH(
      available.left + left,
      available.top + top,
      view.width.toDouble(),
      view.height.toDouble(),
    );
    bounds[view] = rectangle;
    final linear = vm.assignable(
      view.object.className,
      'Landroid/widget/LinearLayout;',
    );
    var next = rectangle;
    for (final child in view.children) {
      final state = environment.views[child];
      if (state == null) {
        throw MissingDalvikBridge('Child view has no host state');
      }
      _place(state, next);
      if (linear && state.visibility != 8) {
        final placed = bounds[state]!;
        next = view.orientation == 1
            ? Rect.fromLTRB(
                next.left,
                math.min(next.bottom, placed.bottom),
                next.right,
                next.bottom,
              )
            : Rect.fromLTRB(
                math.min(next.right, placed.right),
                next.top,
                next.right,
                next.bottom,
              );
      }
    }
  }
}
