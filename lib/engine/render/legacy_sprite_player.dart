import '../assets/sprite.dart';

/// Instance animation state from GLLibPlayer (t.java).
/// Audio/static tile-renderer functions in that class belong to other systems.
final class LegacySpritePlayer {
  LegacySpritePlayer({
    GameSprite? sprite,
    this.framesPerSecond = 25,
    this.singleStepPerUpdate = false,
    this.paintAfterCompletion = false,
    this.x = 0,
    this.y = 0,
  }) {
    if (framesPerSecond < 1 || framesPerSecond > 1000) {
      throw RangeError.range(framesPerSecond, 1, 1000);
    }
    if (sprite != null) bind(sprite);
  }

  final int framesPerSecond;

  /// Original p.o0=false. When enabled, at most one frame advances per update.
  final bool singleStepPerUpdate;

  /// Original p.v1=false.
  final bool paintAfterCompletion;
  GameSprite? sprite;
  int x, y;
  int transform = 0;
  int animation = -1, animationFrame = 0, elapsed = 0, unitDuration = 0;
  int loopsRemaining = 1, palette = -1, scalePercent = -1, alpha = -1;
  bool completed = true;

  GameSprite get _sprite => sprite ?? (throw StateError('Sprite is not set'));
  SpriteAnimationFrame? get currentStep {
    if (sprite == null || animation < 0) return null;
    final a = _sprite.animations[animation];
    return _sprite.animationFrames[a.start + animationFrame];
  }

  int get currentFrame => currentStep?.frame ?? -1;
  int get currentDuration =>
      animation < 0 ? 0 : currentStep!.time * unitDuration;
  bool get isOver => animation < 0 || (loopsRemaining >= 0 && completed);
  bool get shouldPaint =>
      animation >= 0 && (paintAfterCompletion || !completed);
  int frameCount(int id, {bool compressed = true}) {
    final data = _sprite;
    if (id < 0) return -1;
    final a = data.animations[id];
    if (compressed) return a.count;
    var total = 0;
    for (var i = 0; i < a.count; i++) {
      total += data.animationFrames[a.start + i].time;
    }
    return total;
  }

  void reset() {
    x = 0;
    y = 0;
    animation = -1;
    animationFrame = 0;
    sprite = null;
    transform = 0;
    elapsed = 0;
    loopsRemaining = 1;
    palette = -1;
    completed = true;
    scalePercent = -1;
    alpha = -1;
    // Original l() does not reset u0 (unitDuration).
  }

  void bind(GameSprite? value) {
    sprite = value;
    if (value == null) {
      animation = -1;
    } else {
      setAnimation(-1, loops: -1);
    }
  }

  void setAnimation(int id, {required int loops, int totalDuration = -1}) {
    final data = _sprite;
    if (id < -1 || id >= data.animations.length) {
      throw RangeError.range(id, -1, data.animations.length - 1, 'animation');
    }
    if (loops == 0) {
      throw ArgumentError.value(loops, 'loops', 'Use -1 for infinite looping');
    }
    if (completed || id != animation) {
      animation = id;
      unitDuration = totalDuration == -1
          ? 1000 ~/ framesPerSecond
          : totalDuration ~/ frameCount(id, compressed: false);
      setFrame(0);
      loopsRemaining = (loops - 1).toSigned(32);
      completed = false;
    }
  }

  int setFrame(int index) {
    _sprite;
    if (index < 0) throw RangeError.value(index, 'frame');
    if (animation < 0) return -1;
    animationFrame = index % frameCount(animation);
    elapsed = 0;
    return animationFrame;
  }

  /// Applies the original javax.microedition Sprite transform mapping.
  /// Out-of-range codes leave the prior transform intact, as original r().
  void setTransform(int code) {
    const values = [0, 2, 1, 3, 5, 4, 7, 6];
    if (code >= 0 && code < values.length) transform = values[code];
  }

  void update(int deltaMilliseconds) {
    if (deltaMilliseconds < 0) {
      throw RangeError.value(deltaMilliseconds, 'deltaMilliseconds');
    }
    if (completed || animation < 0) return;
    var duration = currentDuration;
    if (duration == 0) return;
    while (elapsed >= duration) {
      elapsed -= duration;
      if (animationFrame < frameCount(animation) - 1) {
        animationFrame++;
      } else if (loopsRemaining == 0) {
        completed = true;
        break;
      } else {
        if (loopsRemaining > 0) loopsRemaining--;
        animationFrame = 0;
      }
      if (singleStepPerUpdate) break;
      duration = currentDuration;
      if (duration == 0) break;
    }
    // Preserve the original ordering: consume PREVIOUS elapsed time first.
    elapsed = (elapsed + deltaMilliseconds).toSigned(32);
  }
}
