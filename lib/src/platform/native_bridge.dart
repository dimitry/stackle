import 'package:flutter/services.dart';

class NativeBridge {
  NativeBridge();

  static const MethodChannel _channel = MethodChannel('stackle/native');

  Future<void> Function(String text)? _quickAddHandler;
  bool _handlerRegistered = false;

  Future<void> initialize({
    required Future<void> Function(String text) onQuickAdd,
  }) async {
    _quickAddHandler = onQuickAdd;
    if (_handlerRegistered) {
      return;
    }
    _channel.setMethodCallHandler(_handleNativeMethod);
    _handlerRegistered = true;
  }

  Future<void> showQuickAddOverlay() async {
    await _invokeWithRetry<void>('showQuickAddPanel');
  }

  Future<String?> selectDatabasePathForCreate() async {
    return _invokeWithRetry<String>('selectDatabasePathForCreate');
  }

  Future<String?> selectDatabasePathForOpen() async {
    return _invokeWithRetry<String>('selectDatabasePathForOpen');
  }

  Future<void> activateApp() async {
    await _invokeWithRetry<void>('activateApp');
  }

  Future<void> hideMainWindow() async {
    await _invokeWithRetry<void>('hideMainWindow');
  }

  Future<bool> isAccessibilityTrusted() async {
    final trusted = await _invokeWithRetry<bool>('isAccessibilityTrusted');
    return trusted ?? false;
  }

  Future<void> openAccessibilitySettings() async {
    await _invokeWithRetry<void>('openAccessibilitySettings');
  }

  Future<void> quitApp() async {
    await _invokeWithRetry<void>('quitApp');
  }

  Future<void> setMainWindowHeight(double height) async {
    await _invokeWithRetry<void>('setMainWindowHeight', arguments: height);
  }

  Future<void> _handleNativeMethod(MethodCall call) async {
    switch (call.method) {
      case 'quickAddSubmitted':
        final text = (call.arguments as String? ?? '').trim();
        if (text.isNotEmpty && _quickAddHandler != null) {
          await _quickAddHandler!(text);
        }
        return;
      default:
        throw MissingPluginException('Unhandled native method: ${call.method}');
    }
  }

  Future<T?> _invokeWithRetry<T>(String method, {Object? arguments}) async {
    const maxAttempts = 6;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await _channel.invokeMethod<T>(method, arguments);
      } on MissingPluginException {
        if (attempt == maxAttempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 140));
      }
    }
    return null;
  }
}
