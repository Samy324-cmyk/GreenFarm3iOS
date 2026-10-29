import 'dart:typed_data';

final class LegacyPath {
  const LegacyPath(this.mapWidth, this.reverseIndices);
  final int mapWidth;

  /// Original GLLib order: destination first, starting tile last.
  final List<int> reverseIndices;
  bool get found => reverseIndices.isNotEmpty;
  int get length => reverseIndices.length;
  List<int> get forwardIndices => List.unmodifiable(reverseIndices.reversed);
  int xAt(int index) => reverseIndices[index] % mapWidth;
  int yAt(int index) => reverseIndices[index] ~/ mapWidth;
}

/// Original GLLibPathFinding A*, including stable ties and signed-short scores.
/// This preserves observed quirks; it is not a replacement generic A* library.
final class LegacyPathfinding {
  LegacyPathfinding({
    required this.width,
    required this.height,
    required this.collision,
    required this.straightCost,
    required this.diagonalCost,
    required this.turnCost,
    required this.directionCount,
    this.blockedMask = -1,
    this.capacity = 9216,
    this.softWalls = false,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width * height > 32767 ||
        collision.length != width * height) {
      throw ArgumentError('Invalid collision grid dimensions');
    }
    if (directionCount != 4 && directionCount != 8) {
      throw ArgumentError.value(directionCount, 'directionCount');
    }
    if (capacity < 1 || capacity > 32767) {
      throw RangeError.range(capacity, 1, 32767, 'capacity');
    }
    _parent = Int16List(capacity);
    _previous = Int16List(capacity);
    _next = Int16List(capacity);
    _cost = Int16List(capacity);
    _heuristic = Int16List(capacity);
  }
  final int width,
      height,
      straightCost,
      diagonalCost,
      turnCost,
      directionCount,
      blockedMask,
      capacity;

  /// Original p.w2=false. The optional original branch permits expensive walls.
  final bool softWalls;

  /// The original engine retains this map reference so game edits remain visible.
  final Uint8List collision;
  late final Int16List _parent, _previous, _next, _cost, _heuristic;
  int _head = -1;
  static const _dx = [0, 0, -1, 1, -1, 1, -1, 1];
  static const _dy = [-1, 1, 0, 0, -1, -1, 1, 1];

  bool _blocked(int x, int y) => collision[y * width + x] & blockedMask != 0;

  LegacyPath find({
    required int startX,
    required int startY,
    required int initialDirection,
    required int targetX,
    required int targetY,
    int regionX = 0,
    int regionY = 0,
    int? regionWidth,
    int? regionHeight,
    bool directionMaskMode = false,
  }) {
    var rw = regionWidth ?? width, rh = regionHeight ?? height;
    if (regionX < 0) {
      rw += regionX;
      regionX = 0;
    }
    if (regionY < 0) {
      rh += regionY;
      regionY = 0;
    }
    if (rw <= 0 ||
        rh <= 0 ||
        rw * rh > capacity ||
        regionX + rw > width ||
        regionY + rh > height) {
      throw ArgumentError(
        'Invalid search region or insufficient node capacity',
      );
    }
    if (startX < regionX ||
        startX >= regionX + rw ||
        startY < regionY ||
        startY >= regionY + rh) {
      throw RangeError('Start is outside search region');
    }
    _parent.fillRange(0, capacity, -1);
    _previous.fillRange(0, capacity, -1);
    _next.fillRange(0, capacity, -1);
    _cost.fillRange(0, capacity, 0);
    _heuristic.fillRange(0, capacity, 0);
    _head = -1;
    final start = (startY - regionY) * rw + startX - regionX;
    final tx = targetX - regionX, ty = targetY - regionY;
    var current = start, direction = initialDirection;
    while (current != -1) {
      _remove(current);
      final currentCost = _cost[current];
      _cost[current] = -1;
      _heuristic[current] = -1;
      final cx = current % rw, cy = current ~/ rw;
      if (cx == tx && cy == ty) break;
      for (var d = 0; d < directionCount; d++) {
        // The bytecode uses local cx/cy here even for a sub-region. Preserve it.
        if (directionMaskMode &&
            collision[cy * width + cx] & blockedMask & (1 << d) == 0) {
          continue;
        }
        final nx = cx + _dx[d], ny = cy + _dy[d];
        if (nx < 0 || nx >= rw || ny < 0 || ny >= rh) continue;
        final adjacent = ny * rw + nx;
        if (_cost[adjacent] == -1) continue;
        int step;
        if (softWalls) {
          step = _softStep(
            cx + regionX,
            cy + regionY,
            nx + regionX,
            ny + regionY,
            d,
            current == start,
          );
        } else {
          step = d < 4 ? straightCost : diagonalCost;
          if (!directionMaskMode) {
            if (d >= 4 &&
                (_blocked(cx + _dx[d] + regionX, cy + regionY) ||
                    _blocked(cx + regionX, cy + _dy[d] + regionY))) {
              continue;
            }
            if (_blocked(nx + regionX, ny + regionY)) continue;
          }
        }
        final tentative = (currentCost + step + (direction == d ? 0 : turnCost))
            .toSigned(32);
        final ax = (nx - tx).abs(), ay = (ny - ty).abs();
        final estimate = directionCount == 4
            ? straightCost * (ax + ay)
            : diagonalCost * (ax < ay ? ax : ay) +
                  straightCost * (ax - ay).abs();
        if (_previous[adjacent] == -1 &&
            _next[adjacent] == -1 &&
            _head != adjacent) {
          _parent[adjacent] = current;
          _cost[adjacent] = tentative;
          _heuristic[adjacent] = estimate;
          _insert(adjacent);
        } else if (_cost[adjacent] > tentative) {
          _parent[adjacent] = current;
          _cost[adjacent] = tentative;
          _remove(adjacent);
          _insert(adjacent);
        }
      }
      current = _head;
      if (current != -1) {
        final parent = _parent[current];
        final x = current % rw, px = parent % rw;
        // Original bytecode L4de uses != for Y, not >. Both vertical directions
        // become 1, and a diagonal uses its horizontal component. Keep the quirk.
        direction = x != px
            ? (x > px ? 3 : 2)
            : (current ~/ rw != parent ~/ rw ? 1 : 0);
      }
    }
    if (current == -1) return LegacyPath(width, const []);
    final reversed = <int>[];
    while (current != -1) {
      reversed.add(
        (((current ~/ rw) + regionY) * width + current % rw + regionX).toSigned(
          16,
        ),
      );
      current = _parent[current];
    }
    return LegacyPath(width, List.unmodifiable(reversed));
  }

  int _softStep(int x, int y, int nx, int ny, int direction, bool isStart) {
    var step = straightCost;
    final penalty = (straightCost * 1000).toSigned(32);
    final insideWall = !isStart && _blocked(x, y);
    if (direction >= 4) {
      step = diagonalCost;
      if (!insideWall &&
          (_blocked(x + _dx[direction], y) ||
              _blocked(x, y + _dy[direction]))) {
        step = (step + penalty).toSigned(32);
      }
    }
    if (!_blocked(nx, ny)) return step;
    if (insideWall) return (step + straightCost * 10).toSigned(32);
    return step < penalty ? (step + penalty).toSigned(32) : step;
  }

  void _insert(int node) {
    if (_head == -1) {
      _head = node;
      return;
    }
    final score = _cost[node] + _heuristic[node];
    var cursor = _head;
    while (cursor != -1) {
      // Strict < means equal-score neighbors retain their insertion order.
      if (score < _cost[cursor] + _heuristic[cursor]) {
        if (_previous[cursor] == -1) {
          _head = node;
        } else {
          _next[_previous[cursor]] = node;
        }
        _previous[node] = _previous[cursor];
        _next[node] = cursor;
        _previous[cursor] = node;
        return;
      }
      if (_next[cursor] == -1) {
        _next[cursor] = node;
        _previous[node] = cursor;
        return;
      }
      cursor = _next[cursor];
    }
  }

  void _remove(int node) {
    if (_next[node] != -1) _previous[_next[node]] = _previous[node];
    if (_head == node) {
      _head = _next[node];
    } else if (_previous[node] != -1) {
      _next[_previous[node]] = _next[node];
    }
    _previous[node] = -1;
    _next[node] = -1;
  }
}
