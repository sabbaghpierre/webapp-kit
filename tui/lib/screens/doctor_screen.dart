/// Doctor screen: per-app health rows + orphans.
library;

import 'package:nocterm/nocterm.dart';

import '../backend.dart';
import '../models.dart';

class DoctorScreen extends StatefulComponent {
  final Backend backend;
  final VoidCallback onBack;

  const DoctorScreen({super.key, required this.backend, required this.onBack});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  DoctorReport? report;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      report = null;
      error = null;
    });
    try {
      final loaded = await component.backend.doctor();
      if (!mounted) return;
      setState(() => report = loaded);
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    }
  }

  bool _onKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      component.onBack();
      return true;
    }
    if (event.character == 'r') {
      _load();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final rep = report;
    final err = error;
    return Focusable(
      focused: true,
      onKeyEvent: (event) => _onKey(event),
      child: Container(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Doctor (r: refresh · Esc: back)',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.yellow)),
            const SizedBox(height: 1),
            if (err != null)
              Text('Error: $err',
                  style: const TextStyle(color: Colors.brightRed))
            else if (rep == null)
              const Text('Checking…')
            else if (rep.apps.isEmpty && rep.orphans.isEmpty)
              const Text('No webapps installed.')
            else
              Expanded(
                child: ListView(
                  keyboardScrollable: true,
                  children: [
                    for (final app in rep.apps) ..._appRows(app),
                    for (final orphan in rep.orphans)
                      Text('orphan: $orphan',
                          style:
                              const TextStyle(color: Colors.brightRed)),
                  ],
                ),
              ),
            if (rep != null) ...[
              const SizedBox(height: 1),
              Text(
                rep.issueCount == 0
                    ? 'all green'
                    : '${rep.issueCount} warning(s)',
                style: TextStyle(
                    color: rep.issueCount == 0
                        ? Colors.green
                        : Colors.brightRed),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Component> _appRows(DoctorApp app) {
    final rows = <Component>[
      Text(
        '${app.healthy ? 'ok' : 'WARN'} ${app.name} [${app.engine}]${app.live ? ' (running)' : ''}',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            color: app.healthy ? Colors.green : Colors.brightRed),
      ),
    ];
    for (final issue in app.issues) {
      rows.add(Text('  - $issue'));
    }
    return rows;
  }
}
