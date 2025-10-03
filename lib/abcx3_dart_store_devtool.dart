library abcx3_dart_store_devtool;

import 'dart:async';
import 'dart:developer' as developer;

/// Event kind used by the DevTools extension to display store updates
const String abcx3StoresDevToolsEventKind = 'Abcx3Stores';

/// Represents a single store feed you want to observe
class StoreFeed {
  final String name;
  final Stream<List<dynamic>> items$;

  /// Optional transform to turn a model instance into a JSON-like map
  /// If omitted, we will attempt to call `toJson()` on each item.
  final Map<String, dynamic> Function(dynamic item)? toJson;

  StoreFeed({required this.name, required this.items$, this.toJson});
}

/// Lightweight bridge that subscribes to store item streams and posts
/// snapshots to Flutter DevTools via `developer.postEvent`.
class Abcx3StoresDevtool {
  static final List<StreamSubscription> _subs = <StreamSubscription>[];
  static bool _running = false;

  /// Start observing provided [feeds] and post snapshots to DevTools.
  static void start(List<StoreFeed> feeds) {
    if (_running) return;
    _running = true;
    for (final feed in feeds) {
      final sub = feed.items$.listen((items) {
        // Serialize each item
        final serialized = items.map((item) {
          try {
            if (feed.toJson != null) return feed.toJson!(item);
            final dynamic dyn = item;
            final dynamic maybeJson = dyn.toJson();
            if (maybeJson is Map<String, dynamic>) return maybeJson;
            if (maybeJson is Map) return Map<String, dynamic>.from(maybeJson as Map);
          } catch (_) {}
          // Fallback for non-serializable items
          return <String, dynamic>{'value': item.toString()};
        }).toList(growable: false);

        // Post to DevTools extension consumers
        developer.postEvent(abcx3StoresDevToolsEventKind, <String, dynamic>{
          'store': feed.name,
          'count': serialized.length,
          'items': serialized,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
      });
      _subs.add(sub);
    }
  }

  /// Manually post a snapshot (optional helper if needed).
  static void postSnapshot(String storeName, List<Map<String, dynamic>> items) {
    developer.postEvent(abcx3StoresDevToolsEventKind, <String, dynamic>{
      'store': storeName,
      'count': items.length,
      'items': items,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Stop and release subscriptions.
  static Future<void> stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _running = false;
  }
}

