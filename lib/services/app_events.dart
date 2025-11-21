import 'dart:async';

/// Simple app-wide event bus for UI pages to notify each other about data
/// changes (e.g., posts created/updated/deleted). Keep minimal to avoid
/// heavy dependencies.
class AppEvents {
  // Broadcast controller so multiple listeners can subscribe
  static final StreamController<void> _dataChangedController = StreamController<void>.broadcast();

  /// Stream that pages can listen to for data-change events.
  static Stream<void> get onDataChanged => _dataChangedController.stream;

  /// Emit a data-change event.
  static void notifyDataChanged() {
    try {
      _dataChangedController.add(null);
    } catch (_) {
      // ignore
    }
  }

  /// Dispose the controller (not usually needed during app lifetime)
  static Future<void> dispose() async {
    await _dataChangedController.close();
  }
}
