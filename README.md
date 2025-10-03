# ABCx3 Dart Store DevTool

A lightweight DevTools extension + in-app bridge to visualize all ABCx3 generated stores (`ModelStreamStore` descendants) as they change.

## What it does
- Subscribes to each store’s `items$` stream in your app (via a tiny setup helper inside the app).
- Posts snapshots to DevTools using `developer.postEvent` under the event kind `Abcx3Stores`.
- DevTools extension UI displays a two‑column view: store list (left) and JSON content (right) with expandable nested structures.

## Host app integration
In your Flutter app:

- Add path dependency (already wired in `abcx3_flutter/pubspec.yaml`):

```
devtools:
  extensions:
    - abcx3_dart_store_devtool

dependencies:
  abcx3_dart_store_devtool:
    path: ../abcx3_dart_store_devtool/
```

- Call the setup function in debug builds (already wired in `lib/main.dart`):

```
import 'package:abcx3/setup_stores_devtool.dart';
...
setupAbcx3StoresDevTool();
```

This registers listeners for all generated stores and streams their updates to DevTools.

## Build the DevTools extension UI
From this package folder:

```
flutter pub get
flutter build web -t extension/devtools/lib/extension_main.dart --web-renderer canvaskit -o extension/devtools/build
```

Restart Flutter DevTools; the “ABCx3 Stores” tab should appear.

## Event shape
The app posts updates with this payload under event kind `Abcx3Stores`:

```
{
  "store": "TileStore",
  "count": 42,
  "items": [ { ...model json... }, ... ],
  "ts": 1735920000000
}
```

## Notes
- Models are serialized via `toJson()` when available; otherwise a string fallback is used.
- This devtool is non-intrusive and only active in debug builds.
- Extend the UI to add filters, search, or diffing as needed.

