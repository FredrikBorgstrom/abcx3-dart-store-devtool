import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:devtools_extensions/src/api/api.dart';
import 'package:flutter/material.dart';
import 'package:vm_service/vm_service.dart' as vm;

// Matches the event name posted by the app via developer.postEvent
const String _eventKind = 'Abcx3Stores';

void main() {
  runApp(const DevToolsExtension(child: _StoresExtensionApp()));
}

class _StoresExtensionApp extends StatefulWidget {
  const _StoresExtensionApp();
  @override
  State<_StoresExtensionApp> createState() => _StoresExtensionAppState();
}

class _StoresExtensionAppState extends State<_StoresExtensionApp> {
  final Map<String, List<Map<String, dynamic>>> _storeData = {};
  final List<String> _storeNames = [];
  String? _selected;
  StreamSubscription<vm.Event>? _sub;
  VoidCallback? _connListener;

  // Theme override: follow host (DevTools), force light, or force dark.
  ThemeOverride _themeOverride = ThemeOverride.followHost;

  // Search / filter and sorting
  final TextEditingController _searchCtrl = TextEditingController();
  String? _sortKey; // null => no sort
  bool _sortAsc = true;
  bool _expandAllItems = false;

  @override
  void initState() {
    super.initState();
    // Start with a dark default so it's immediately visible,
    // then allow users to choose how to handle theme.
    _applyThemeOverride(ThemeOverride.dark);

    // If running inside DevTools, react to theme updates only when following host.
    extensionManager
        .registerEventHandler(DevToolsExtensionEventType.themeUpdate, (_) {
      if (_themeOverride == ThemeOverride.followHost) {
        // Do nothing: DevToolsExtension already updated extensionManager.darkThemeEnabled.
        setState(() {});
      } else {
        // Re-apply our override in case the host tried to change it.
        _applyThemeOverride(_themeOverride);
      }
    });
    _connListener = () {
      final connected = serviceManager.connectedState.value.connected;
      if (connected && _sub == null) {
        _sub = serviceManager.service!.onExtensionEvent.listen((event) {
          if (event.extensionKind != _eventKind) return;
          final data = event.extensionData?.data;
          if (data is Map) {
            final map = Map<String, dynamic>.from(data as Map);
            final String store = map['store']?.toString() ?? 'unknown';
            final List<dynamic> items = (map['items'] as List<dynamic>? ?? []);
            final List<Map<String, dynamic>> rows = items
                .map((e) => e is Map<String, dynamic>
                    ? e
                    : e is Map
                        ? Map<String, dynamic>.from(e)
                        : <String, dynamic>{'value': e.toString()})
                .toList(growable: false);
            setState(() {
              _storeData[store] = rows;
              if (!_storeNames.contains(store)) _storeNames.add(store);
              _storeNames.sort((a, b) => a.compareTo(b));
              _selected ??= store;
            });
          }
        });
      }
    };
    serviceManager.connectedState.addListener(_connListener!);
    // Kick once in case we are already connected
    _connListener!.call();
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_connListener!);
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: extensionManager.darkThemeEnabled.value
            ? Brightness.dark
            : Brightness.light,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('ABCx3 Stores'),
          actions: [
            _buildThemeMenu(),
          ],
        ),
        body: Row(
          children: [
            SizedBox(
              width: 260,
              child: ListView.builder(
                itemCount: _storeNames.length,
                itemBuilder: (context, index) {
                  final name = _storeNames[index];
                  final count = _storeData[name]?.length ?? 0;
                  final selected = name == _selected;
                  return ListTile(
                    selected: selected,
                    title: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: CircleAvatar(
                      radius: 12,
                      child:
                          Text('$count', style: const TextStyle(fontSize: 12)),
                    ),
                    onTap: () => setState(() => _selected = name),
                  );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeMenu() {
    return PopupMenuButton<ThemeOverride>(
      tooltip: 'Theme',
      icon: const Icon(Icons.brightness_6),
      initialValue: _themeOverride,
      onSelected: (value) {
        setState(() {
          _applyThemeOverride(value);
        });
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: ThemeOverride.followHost,
          child: Text('Follow DevTools theme'),
        ),
        PopupMenuItem(
          value: ThemeOverride.light,
          child: Text('Force Light'),
        ),
        PopupMenuItem(
          value: ThemeOverride.dark,
          child: Text('Force Dark'),
        ),
      ],
    );
  }

  void _applyThemeOverride(ThemeOverride value) {
    _themeOverride = value;
    switch (value) {
      case ThemeOverride.followHost:
        // No-op: DevToolsExtension will drive theme via extensionManager.
        break;
      case ThemeOverride.light:
        extensionManager.darkThemeEnabled.value = false;
        break;
      case ThemeOverride.dark:
        extensionManager.darkThemeEnabled.value = true;
        break;
    }
  }

  Widget _buildContent() {
    final sel = _selected;
    final rows = sel == null
        ? const <Map<String, dynamic>>[]
        : (_storeData[sel] ?? const []);
    if (sel == null) {
      return const Center(child: Text('Select a store on the left'));
    }
    if (rows.isEmpty) {
      return Center(child: Text('$sel is empty'));
    }
    // Build controls + filtered, sorted content
    final filtered = _applyFilter(rows, _searchCtrl.text);
    final sorted = _applySort(filtered, _sortKey, asc: _sortAsc);
    final keys = _availableSortKeys(rows);
    _sortKey ??=
        keys.contains('id') ? 'id' : (keys.isNotEmpty ? keys.first : null);

    return Column(
      children: [
        _controlsBar(sel,
            total: rows.length, visible: sorted.length, keys: keys),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemCount: sorted.length,
            itemBuilder: (context, idx) {
              return _StoreItemTile(
                key: ValueKey(
                    'item-$sel-$idx-${_expandAllItems ? 'exp' : 'col'}'),
                map: sorted[idx],
                globalExpandAll: _expandAllItems,
                itemIndex: idx,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _controlsBar(String storeName,
      {required int total, required int visible, required List<String> keys}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          // Search
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search in $storeName…',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _searchCtrl.clear()),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          // Sort key
          DropdownButton<String>(
            value: _sortKey,
            hint: const Text('Sort by'),
            items: keys
                .map((k) => DropdownMenuItem<String>(value: k, child: Text(k)))
                .toList(),
            onChanged: (v) => setState(() => _sortKey = v),
          ),
          IconButton(
            tooltip: _sortAsc ? 'Ascending' : 'Descending',
            icon: Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
          ),
          const SizedBox(width: 12),
          // Expand/collapse all items
          Tooltip(
            message:
                _expandAllItems ? 'Collapse all items' : 'Expand all items',
            child: IconButton(
              icon:
                  Icon(_expandAllItems ? Icons.unfold_less : Icons.unfold_more),
              onPressed: () =>
                  setState(() => _expandAllItems = !_expandAllItems),
            ),
          ),
          const SizedBox(width: 8),
          // Counts
          Chip(
            label: Text('$visible / $total'),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          // Copy all button
          Tooltip(
            message: 'Copy visible as JSON',
            child: IconButton(
              icon: const Icon(Icons.content_copy),
              onPressed: () {
                final pretty = const JsonEncoder.withIndent('  ').convert(
                  visible == total
                      ? (_storeData[storeName] ?? const [])
                      : _applySort(
                          _applyFilter(_storeData[storeName] ?? const [],
                              _searchCtrl.text),
                          _sortKey,
                          asc: _sortAsc,
                        ),
                );
                extensionManager.copyToClipboard(pretty);
                extensionManager.showNotification(
                    'Copied $visible item(s) from $storeName');
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> rows, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((m) => _mapContains(m, q)).toList(growable: false);
  }

  bool _mapContains(Map<String, dynamic> m, String q) {
    for (final e in m.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is Map<String, dynamic>) {
        if (_mapContains(v, q)) return true;
      } else if (v is List) {
        for (final el in v) {
          if (el is Map<String, dynamic>) {
            if (_mapContains(el, q)) return true;
          } else if (el != null && el.toString().toLowerCase().contains(q)) {
            return true;
          }
        }
      } else if (v.toString().toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> _applySort(
    List<Map<String, dynamic>> rows,
    String? key, {
    required bool asc,
  }) {
    if (key == null) return rows;
    final copy = [...rows];
    int cmp(dynamic a, dynamic b) {
      // Try numeric if both parse
      final da = _toComparable(a);
      final db = _toComparable(b);
      if (da is num && db is num) return da.compareTo(db);
      return da.toString().compareTo(db.toString());
    }

    copy.sort((a, b) => asc ? cmp(a[key], b[key]) : cmp(b[key], a[key]));
    return copy;
  }

  dynamic _toComparable(dynamic v) {
    if (v == null) return '';
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    // ISO date strings sort OK as strings; attempt DateTime parse for robustness
    if (v is String) {
      final dt = DateTime.tryParse(v);
      return dt?.millisecondsSinceEpoch ?? v;
    }
    return v;
  }

  List<String> _availableSortKeys(List<Map<String, dynamic>> rows) {
    final keys = <String>{};
    for (final m in rows.take(100)) {
      for (final e in m.entries) {
        if (_isPrimitiveGlobal(e.value)) keys.add(e.key);
      }
    }
    final list = keys.toList()..sort();
    return list;
  }

  // Global primitive check usable from this state object
  bool _isPrimitiveGlobal(dynamic v) =>
      v == null || v is num || v is String || v is bool;
}

enum ThemeOverride { followHost, light, dark }

/// Card-based item with a compact summary on the header; expands to full JSON.
class _StoreItemTile extends StatefulWidget {
  final Map<String, dynamic> map;
  final bool globalExpandAll;
  final int itemIndex;
  const _StoreItemTile(
      {super.key,
      required this.map,
      required this.globalExpandAll,
      required this.itemIndex});

  @override
  State<_StoreItemTile> createState() => _StoreItemTileState();
}

class _StoreItemTileState extends State<_StoreItemTile> {
  bool _expanded = false;
  bool _expandAll = false;
  bool _showJson = false;

  @override
  void initState() {
    super.initState();
    _expandAll = widget.globalExpandAll;
    _expanded = widget.globalExpandAll || _expanded;
  }

  @override
  void didUpdateWidget(covariant _StoreItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.globalExpandAll != widget.globalExpandAll) {
      setState(() {
        _expandAll = widget.globalExpandAll;
        _expanded = widget.globalExpandAll || _expanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface.withValues(alpha: 0.9);
    final shadow = theme.colorScheme.shadow.withValues(alpha: 0.08);

    final summary = _buildSummary(widget.map);
    final summaryKeys = summary.map((e) => e.key).toSet();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        onExpansionChanged: (v) => setState(() {
          _expanded = v;
          if (v) {
            // When user opens a row, show all nested data by default.
            _expandAll = true;
          }
        }),
        initiallyExpanded: _expanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: summary.isNotEmpty
              ? summary.map((e) => _chip(context, e.key, e.value)).toList()
              : [
                  Text('{…}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: onSurface))
                ],
        ),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: Icon(_expandAll ? Icons.unfold_less : Icons.unfold_more,
                      size: 18),
                  label: Text(_expandAll ? 'Collapse all' : 'Expand all'),
                  onPressed: () => setState(() => _expandAll = !_expandAll),
                ),
                TextButton.icon(
                  icon: Icon(
                      _showJson ? Icons.visibility_off : Icons.visibility,
                      size: 18),
                  label: Text(_showJson ? 'Hide JSON' : 'Show JSON'),
                  onPressed: () => setState(() => _showJson = !_showJson),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: const Text('Copy JSON'),
                  onPressed: () {
                    final pretty =
                        const JsonEncoder.withIndent('  ').convert(widget.map);
                    extensionManager.copyToClipboard(pretty);
                    extensionManager.showNotification('Copied item JSON');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Render remaining primitive fields as pills, then nested objects.
          _MapPillView(
            map: widget.map,
            expandAll: _expandAll,
            excludeKeys: summaryKeys,
            key: ValueKey(
                'root-map-${widget.itemIndex}-${_expandAll ? 'exp' : 'col'}'),
          ),
          if (_showJson) ...[
            const SizedBox(height: 8),
            _JsonTile(
              key: ValueKey(
                  'json-${widget.itemIndex}-${_expandAll ? 'exp' : 'col'}-${_showJson ? 'show' : 'hide'}'),
              data: widget.map,
              expandAll: _expandAll,
            ),
          ],
        ],
      ),
    );
  }

  Iterable<MapEntry<String, String>> _buildSummary(Map<String, dynamic> m) {
    // Prefer common keys if present; otherwise take first 4 primitive fields.
    const preferred = [
      'id',
      'name',
      'title',
      'letter',
      'userId',
      'gameId',
      'bagId',
      'points',
      'email',
      'providerName',
      'createdAt',
      'updatedAt'
    ];

    Map<String, String> picked = {};

    for (final k in preferred) {
      if (m.containsKey(k) && _isPrimitive(m[k])) {
        picked[k] = _fmt(m[k]);
      }
    }

    if (picked.length < 4) {
      for (final e in m.entries) {
        if (picked.length >= 4) break;
        if (picked.containsKey(e.key)) continue;
        if (_isPrimitive(e.value)) picked[e.key] = _fmt(e.value);
      }
    }

    return picked.entries;
  }

  bool _isPrimitive(dynamic v) =>
      v == null || v is num || v is String || v is bool;

  String _fmt(dynamic v) {
    if (v == null) return 'null';
    final s = v.toString();
    // Compact long strings
    return s.length > 60 ? '${s.substring(0, 57)}…' : s;
  }

  Widget _chip(BuildContext context, String key, String value) {
    final theme = Theme.of(context);
    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      label: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$key: ',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple expandable JSON viewer; nested maps/lists are expandable
class _JsonTile extends StatelessWidget {
  final dynamic data;
  final String? label;
  final bool expandAll;
  const _JsonTile(
      {super.key, required this.data, this.label, this.expandAll = false});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data as Map);
      final entries = map.entries.toList();
      return ExpansionTile(
        initiallyExpanded: expandAll,
        title: Text(label ?? '{...}'),
        children: entries
            .map((e) => Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: _JsonTile(
                      data: e.value, label: e.key, expandAll: expandAll),
                ))
            .toList(),
      );
    } else if (data is List) {
      final list = data as List;
      return ExpansionTile(
        initiallyExpanded: expandAll,
        title: Text(label ?? '[${list.length}]'),
        children: [
          for (int i = 0; i < list.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child:
                  _JsonTile(data: list[i], label: '[$i]', expandAll: expandAll),
            )
        ],
      );
    } else {
      return ListTile(
        dense: true,
        title: Text(label ?? '-', style: textStyle),
        subtitle: Text('${data ?? 'null'}', style: textStyle),
      );
    }
  }
}

/// Pill-first renderer for a Map. Primitive fields (string/number/bool/null)
/// are displayed as chips. Nested Maps/Lists are shown after primitives as
/// expandable sections that recursively use the same chip rendering.
class _MapPillView extends StatelessWidget {
  final Map<String, dynamic> map;
  final bool expandAll;
  final Set<String>? excludeKeys;

  const _MapPillView({
    super.key,
    required this.map,
    required this.expandAll,
    this.excludeKeys,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entries = map.entries
        .where((e) => excludeKeys == null || !excludeKeys!.contains(e.key))
        .toList();

    final primitive = <MapEntry<String, dynamic>>[];
    final nested = <MapEntry<String, dynamic>>[];
    for (final e in entries) {
      if (_isPrimitiveAny(e.value)) {
        primitive.add(e);
      } else {
        nested.add(e);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (primitive.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final e in primitive)
                  _pillChip(context, e.key, _fmt(e.value)),
              ],
            ),
          ),
        for (final e in nested)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: ExpansionTile(
              key: ValueKey('map-node-$expandAll-${e.key}'),
              initiallyExpanded: expandAll,
              leading: const Icon(Icons.chevron_right),
              title: Text(
                e.key,
                style: theme.textTheme.titleSmall,
              ),
              childrenPadding:
                  const EdgeInsets.only(left: 12, right: 4, bottom: 8),
              children: [
                if (e.value is Map)
                  _MapPillView(
                    map: Map<String, dynamic>.from(e.value as Map),
                    expandAll: expandAll,
                  )
                else if (e.value is List)
                  _ListPillView(
                    list: e.value as List,
                    expandAll: expandAll,
                  )
                else
                  ListTile(
                    dense: true,
                    title: Text(_fmt(e.value)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  bool _isPrimitiveAny(dynamic v) =>
      v == null || v is num || v is String || v is bool;

  String _fmt(dynamic v) {
    if (v == null) return 'null';
    final s = v.toString();
    return s.length > 80 ? '${s.substring(0, 77)}…' : s;
  }

  Widget _pillChip(BuildContext context, String key, String value) {
    final theme = Theme.of(context);
    return Chip(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      label: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$key: ',
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListPillView extends StatelessWidget {
  final List list;
  final bool expandAll;
  const _ListPillView({required this.list, required this.expandAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Separate primitive vs object items for clarity.
    final prim = <int, dynamic>{};
    final obj = <int, dynamic>{};
    for (var i = 0; i < list.length; i++) {
      final v = list[i];
      if (v == null || v is num || v is String || v is bool) {
        prim[i] = v;
      } else {
        obj[i] = v;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (prim.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final entry in prim.entries)
                  Chip(
                    label: Text('[${entry.key}]: ${_fmt(entry.value)}',
                        style: theme.textTheme.labelMedium),
                  ),
              ],
            ),
          ),
        for (final entry in obj.entries)
          Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: ExpansionTile(
              key: ValueKey('list-node-$expandAll-${entry.key}'),
              initiallyExpanded: expandAll,
              title: Text('[${entry.key}]', style: theme.textTheme.titleSmall),
              childrenPadding:
                  const EdgeInsets.only(left: 12, right: 4, bottom: 8),
              children: [
                if (entry.value is Map)
                  _MapPillView(
                    map: Map<String, dynamic>.from(entry.value as Map),
                    expandAll: expandAll,
                  )
                else if (entry.value is List)
                  _ListPillView(
                    list: entry.value as List,
                    expandAll: expandAll,
                  )
                else
                  ListTile(
                    dense: true,
                    title: Text(_fmt(entry.value)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmt(dynamic v) => v == null ? 'null' : v.toString();
}
