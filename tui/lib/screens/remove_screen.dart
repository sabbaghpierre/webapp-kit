/// Remove screen: checkbox list, purge toggle, inline confirm.
library;

import 'package:nocterm/nocterm.dart';

import '../backend.dart';
import '../models.dart';

class RemoveScreen extends StatefulComponent {
  final Backend backend;
  final VoidCallback onBack;

  const RemoveScreen({super.key, required this.backend, required this.onBack});

  @override
  State<RemoveScreen> createState() => _RemoveScreenState();
}

class _RemoveScreenState extends State<RemoveScreen> {
  List<WebApp>? apps;
  String? error;
  int selected = 0;
  final checked = <int>{};
  bool purge = false;
  bool confirming = false;
  String? result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      apps = null;
      error = null;
    });
    try {
      final loaded = await component.backend.listApps();
      if (!mounted) return;
      setState(() {
        apps = loaded;
        checked.removeWhere((i) => i >= loaded.length);
        if (selected >= loaded.length) selected = 0;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    }
  }

  Future<void> _execute(bool withPurge) async {
    final items = apps ?? const <WebApp>[];
    final names =
        checked.map((i) => items[i].name).toList(growable: false)..sort();
    setState(() {
      confirming = false;
      result = 'Removing…';
    });
    try {
      final r =
          await component.backend.removeApps(names, purge: withPurge);
      if (!mounted) return;
      setState(() {
        result = r.output.trim().isEmpty ? '(done)' : r.output.trim();
        checked.clear();
      });
      await _load();
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => result = e.message);
    }
  }

  bool _onKey(KeyboardEvent event) {
    final items = apps ?? const <WebApp>[];
    if (event.logicalKey == LogicalKey.escape) {
      if (confirming) {
        setState(() => confirming = false);
      } else {
        component.onBack();
      }
      return true;
    }
    if (confirming) {
      final ch = event.character;
      if (ch == 'y') {
        _execute(purge);
        return true;
      }
      if (ch == 'P') {
        _execute(true);
        return true;
      }
      if (ch == 'n') {
        setState(() => confirming = false);
        return true;
      }
      return false;
    }
    if (event.logicalKey == LogicalKey.arrowDown || event.character == 'j') {
      if (items.isNotEmpty) {
        setState(() => selected = (selected + 1) % items.length);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp || event.character == 'k') {
      if (items.isNotEmpty) {
        setState(() => selected = (selected - 1 + items.length) % items.length);
      }
      return true;
    }
    final ch = event.character;
    if (ch == ' ') {
      if (items.isNotEmpty) {
        setState(() {
          if (!checked.remove(selected)) checked.add(selected);
        });
      }
      return true;
    }
    if (ch == 'p') {
      setState(() => purge = !purge);
      return true;
    }
    if (ch == 'y') {
      if (checked.isNotEmpty) setState(() => confirming = true);
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final items = apps;
    final err = error;
    return Focusable(
      focused: true,
      onKeyEvent: (event) => _onKey(event),
      child: Container(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Remove webapps (space: toggle · Esc: back)',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.yellow)),
            const SizedBox(height: 1),
            if (err != null)
              Text('Error: $err',
                  style: const TextStyle(color: Colors.brightRed))
            else if (items == null)
              const Text('Loading…')
            else if (items.isEmpty)
              const Text('No webapps installed.')
            else
              Expanded(
                child: ListView(
                  keyboardScrollable: false,
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _row(items[i], i, i == selected, checked.contains(i)),
                  ],
                ),
              ),
            if (result != null) ...[
              const SizedBox(height: 1),
              Text(result!),
            ],
            const SizedBox(height: 1),
            Text(
              'purge isolated data: ${purge ? 'ON' : 'off'} (p toggles) · '
              '${checked.length} selected · y: delete · Esc: back',
              style: const TextStyle(color: Colors.brightBlack),
            ),
            if (confirming)
              const Text(
                'Delete? y: keep data · P: PURGE data · n: cancel',
                style: TextStyle(color: Colors.brightRed),
              ),
          ],
        ),
      ),
    );
  }

  Component _row(WebApp app, int index, bool isSelected, bool isChecked) {
    final box = isChecked ? '[x]' : '[ ]';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: isSelected
          ? BoxDecoration(color: Color.fromRGB(30, 40, 50))
          : null,
      child: Text(
        '${isSelected ? '>' : ' '} $box ${app.name} [${app.engine}]',
        style: TextStyle(
            color: isSelected ? Colors.brightWhite : Colors.white),
      ),
    );
  }
}
