/// Create wizard: sequential single-field steps (gum-style).
/// One focused TextField per input step (its onKeyEvent handles Esc);
/// selection steps use a local Focusable (no competing focus).
library;

import 'package:nocterm/nocterm.dart';

import '../backend.dart';

enum _Step { name, url, engine, icon, confirm, working, done }

class CreateScreen extends StatefulComponent {
  final Backend backend;
  final VoidCallback onBack;

  const CreateScreen({super.key, required this.backend, required this.onBack});

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  _Step step = _Step.name;
  final nameCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  final iconCtrl = TextEditingController();
  bool engineIsChrome = true;
  String? error;
  String? result;
  bool resultOk = false;

  static const _order = [_Step.name, _Step.url, _Step.engine, _Step.icon];

  void _next() {
    if (step == _Step.name && nameCtrl.text.trim().isEmpty) {
      setState(() => error = 'Name is required.');
      return;
    }
    if (step == _Step.url && urlCtrl.text.trim().isEmpty) {
      setState(() => error = 'URL is required.');
      return;
    }
    setState(() {
      error = null;
      step = _Step.values[_Step.values.indexOf(step) + 1];
    });
  }

  void _back() {
    final i = _order.indexOf(step);
    if (i <= 0) {
      component.onBack();
    } else {
      setState(() {
        error = null;
        step = _order[i - 1];
      });
    }
  }

  /// Field-level key interceptor: Esc goes back, everything else types.
  bool _fieldKeys(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      _back();
      return true;
    }
    return false;
  }

  Future<void> _submit() async {
    setState(() {
      step = _Step.working;
      error = null;
    });
    try {
      final r = await component.backend.createApp(
        name: nameCtrl.text.trim(),
        url: urlCtrl.text.trim(),
        engine: engineIsChrome ? 'chrome' : 'firefox',
        icon: iconCtrl.text.trim().isEmpty ? null : iconCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        result = r.output.trim().isEmpty
            ? (r.ok ? 'Created.' : 'Failed with no output.')
            : r.output.trim();
        resultOk = r.ok;
        step = _Step.done;
      });
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        result = e.message;
        resultOk = false;
        step = _Step.done;
      });
    }
  }

  /// Selection-step keys (engine/confirm/done): no TextField mounted here.
  bool _selectKeys(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      if (step == _Step.confirm || step == _Step.done) {
        component.onBack();
      } else {
        _back();
      }
      return true;
    }
    if (step == _Step.engine) {
      if (event.logicalKey == LogicalKey.arrowUp ||
          event.logicalKey == LogicalKey.arrowDown) {
        setState(() => engineIsChrome = !engineIsChrome);
        return true;
      }
      if (event.logicalKey == LogicalKey.enter) {
        _next();
        return true;
      }
      if (event.character == 'e') {
        setState(() => engineIsChrome = !engineIsChrome);
        return true;
      }
      return false;
    }
    if (step == _Step.confirm) {
      final ch = event.character;
      if (ch == 'y' || event.logicalKey == LogicalKey.enter) {
        _submit();
        return true;
      }
      if (ch == 'n') {
        _back();
        return true;
      }
      return false;
    }
    if (step == _Step.done) {
      component.onBack();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Create webapp (Enter: next · Esc: back)',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow)),
        const SizedBox(height: 1),
        _stepBody(),
        if (error != null) ...[
          const SizedBox(height: 1),
          Text('Error: $error',
              style: const TextStyle(color: Colors.brightRed)),
        ],
      ],
    );
    // Selection steps own a Focusable (no fields mounted); input steps
    // render bare so the focused TextField receives keys exclusively.
    if (step == _Step.engine ||
        step == _Step.confirm ||
        step == _Step.done) {
      return Focusable(
        focused: true,
        onKeyEvent: (event) => _selectKeys(event),
        child: Container(
            padding: const EdgeInsets.all(1), child: body),
      );
    }
    if (step == _Step.working) {
      return Container(
          padding: const EdgeInsets.all(1), child: body);
    }
    return Container(padding: const EdgeInsets.all(1), child: body);
  }

  Component _stepBody() {
    switch (step) {
      case _Step.name:
        return TextField(
          key: const ValueKey('create-name'),
          controller: nameCtrl,
          focused: true,
          placeholder: 'Name — My favorite web app',
          onKeyEvent: (event) => _fieldKeys(event),
          onSubmitted: (_) => _next(),
        );
      case _Step.url:
        return TextField(
          key: const ValueKey('create-url'),
          controller: urlCtrl,
          focused: true,
          placeholder: 'URL — https://example.com',
          onKeyEvent: (event) => _fieldKeys(event),
          onSubmitted: (_) => _next(),
        );
      case _Step.engine:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _engineRow('chrome  (--app SSB window)', engineIsChrome),
            _engineRow('firefox (minimal-UI profile)', !engineIsChrome),
            const SizedBox(height: 1),
            const Text('up/down or e: toggle · Enter: confirm',
                style: TextStyle(color: Colors.brightBlack)),
          ],
        );
      case _Step.icon:
        return TextField(
          key: const ValueKey('create-icon'),
          controller: iconCtrl,
          focused: true,
          placeholder: 'Icon URL or file (empty: auto-fetch favicon)',
          onKeyEvent: (event) => _fieldKeys(event),
          onSubmitted: (_) => _next(),
        );
      case _Step.confirm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Create "${nameCtrl.text.trim()}"?'),
            Text(
                '  ${(engineIsChrome ? 'chrome' : 'firefox')} · ${urlCtrl.text.trim()}${iconCtrl.text.trim().isEmpty ? '' : ' · custom icon'}'),
            const SizedBox(height: 1),
            const Text('y/Enter: create · n/Esc: back'),
          ],
        );
      case _Step.working:
        return const Text('Creating…');
      case _Step.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(result ?? '',
                style: TextStyle(
                    color: resultOk ? Colors.green : Colors.brightRed)),
            const SizedBox(height: 1),
            const Text('Press any key for dashboard.'),
          ],
        );
    }
  }

  Component _engineRow(String label, bool highlighted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      decoration: highlighted
          ? BoxDecoration(color: Color.fromRGB(30, 40, 50))
          : null,
      child: Text('${highlighted ? '>' : ' '} $label',
          style: TextStyle(
              color: highlighted ? Colors.brightWhite : Colors.white)),
    );
  }
}
