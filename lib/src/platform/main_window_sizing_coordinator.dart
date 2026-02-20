import 'dart:async';

class MainWindowSizingCoordinator {
  MainWindowSizingCoordinator({required this.onSetMainWindowHeight});

  static const double _listVerticalPadding = 16;
  static const double _todoRowExtent = 62;
  static const int _maxVisibleRows = 8;
  static const double footerHeight = 48;

  final Future<void> Function(double height) onSetMainWindowHeight;

  double? _lastRequestedWindowHeight;
  int? _lastWindowHeightTodoCount;
  int _windowHeightRequestVersion = 0;
  Timer? _windowHeightDebounce;

  void dispose() {
    _windowHeightDebounce?.cancel();
  }

  void scheduleSync({
    required bool routeIsCurrent,
    required bool mounted,
    required int todoCount,
  }) {
    if (!routeIsCurrent) {
      return;
    }

    if (_lastWindowHeightTodoCount == todoCount) {
      return;
    }
    _lastWindowHeightTodoCount = todoCount;
    final requestVersion = ++_windowHeightRequestVersion;

    _windowHeightDebounce?.cancel();
    _windowHeightDebounce = Timer(const Duration(milliseconds: 180), () async {
      if (!mounted) {
        return;
      }
      if (requestVersion != _windowHeightRequestVersion) {
        return;
      }

      final targetHeight = targetWindowHeightForTodoCount(todoCount);
      if (_lastRequestedWindowHeight != null &&
          (_lastRequestedWindowHeight! - targetHeight).abs() < 1) {
        return;
      }

      _lastRequestedWindowHeight = targetHeight;
      await onSetMainWindowHeight(targetHeight);
    });
  }

  Future<void> setTemporaryHeight(double minHeight) async {
    _windowHeightDebounce?.cancel();
    await onSetMainWindowHeight(minHeight);
  }

  Future<void> restoreHeight({
    required bool mounted,
    required int todoCount,
  }) async {
    _lastWindowHeightTodoCount = null;
    _windowHeightDebounce?.cancel();

    if (!mounted) {
      return;
    }
    final targetHeight = targetWindowHeightForTodoCount(todoCount);
    _lastRequestedWindowHeight = targetHeight;
    await onSetMainWindowHeight(targetHeight);
  }

  double targetWindowHeightForTodoCount(int count) {
    const emptyStateHeight = 140.0;
    const bottomSlack = -2.0;

    if (count <= 0) {
      return footerHeight + _listVerticalPadding + emptyStateHeight;
    }

    final visibleRows = count.clamp(1, _maxVisibleRows);
    return footerHeight +
        _listVerticalPadding +
        (visibleRows * _todoRowExtent) +
        bottomSlack;
  }
}
