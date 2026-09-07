/// Probe screen: stream `webapp-doctor --probe` lines live.
/// Enter starts (focus the app window first), s stops, Esc stops + back.
library;

import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../backend.dart';
import '../models.dart';

class ProbeScreen extends StatefulComponent {
  final Backend backend;
  final VoidCallback onBack;

  const ProbeScreen({super.key, required this.backend, required this.onBack});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  final nameCtrl = TextEditingController();
  final samples = <ProbeSample>[];
  ProbeSession? session;
  StreamSubscription<ProbeSample>? sub;
  String? error;
  bool probing = false;

  Future<void> _start() async {
    await _stop(silent: true);
    final name =
        nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim();
    setState(() {
      samples.clear();
      error = null;
      probing = true;
    });
    try {
      final s = await component.backend.startProbe(name);
      if (!mounted) {
        await s.stop();
        return;
      }
      session = s;
      sub = s.lines.listen(
        (sample) {
          if (!mounted) return;
          setState(() {
            samples.insert(0, sample);
            if (samples.length > 100) samples.removeLast();
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() => probing = false);
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            error = '$e';
            probing = false;
          });
        },
      );
    } on BackendException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        probing = false;
      });
    }
  }

  Future<void> _stop({bool silent = false}) async {
    await sub?.cancel();
    sub = null;
    await session?.stop();
    session = null;
    if (!silent && mounted) setState(() => probing = false);
  }

  bool _fieldKeys(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      component.onBack();
      return true;
    }
    return false;
  }

  bool _probingKeys(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      _stop();
      component.onBack();
      return true;
    }
    if (event.character == 's') {
      _stop();
      return true;
    }
    return false;
  }

  @override
  Component build(BuildContext context) {
    final expectSlug = nameCtrl.text.trim().isEmpty
        ? null
        : slugifyApp(nameCtrl.text.trim());
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Probe live window (Enter: start · s: stop · Esc: back)',
            style:
                TextStyle(fontWeight: FontWeight.bold, color: Colors.yellow)),
        const SizedBox(height: 1),
        TextField(
          key: const ValueKey('probe-name'),
          controller: nameCtrl,
          focused: !probing,
          placeholder: 'App name (empty: sample focused window)',
          onKeyEvent: (event) => _fieldKeys(event),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 1),
        if (error != null)
          Text('Error: $error',
              style: const TextStyle(color: Colors.brightRed)),
        Expanded(
          child: ListView(
            keyboardScrollable: true,
            children: [
              if (samples.isEmpty && !probing)
                const Text('No samples yet. Focus the app window, Enter to start.',
                    style: TextStyle(color: Colors.brightBlack)),
              for (final s in samples) _row(s, expectSlug),
            ],
          ),
        ),
      ],
    );
    // While probing the field is unfocused, so a Focusable can own keys.
    // Otherwise the focused field owns keys exclusively (see _fieldKeys).
    if (probing) {
      return Focusable(
        focused: true,
        onKeyEvent: (event) => _probingKeys(event),
        child: Container(padding: const EdgeInsets.all(1), child: body),
      );
    }
    return Container(padding: const EdgeInsets.all(1), child: body);
  }

  Component _row(ProbeSample s, String? expectSlug) {
    final isMatch =
        expectSlug != null && expectSlug.isNotEmpty && s.klass == expectSlug;
    final text = s.klass != null
        ? 'class=${s.klass} desktop=${s.desktop ?? '(n/a)'} pid=${s.pid ?? '?'} ${s.title ?? ''}'
        : s.raw;
    return Text(
      '${isMatch ? 'MATCH ' : ''}$text',
      style: TextStyle(
          fontWeight: isMatch ? FontWeight.bold : null,
          color: isMatch ? Colors.brightGreen : Colors.white),
    );
  }
}
