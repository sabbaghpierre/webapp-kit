/// End-to-end tests: real Backend against stub webapp-* shell scripts.
/// Stubs live in a temp dir injected into child-process PATH only.
library;

import 'dart:async';
import 'dart:io';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';
import 'package:webapp_tui/app.dart';
import 'package:webapp_tui/backend.dart';
import 'package:webapp_tui/screens/probe_screen.dart';

const _stubListJson =
    '[{"name":"E2EApp","engine":"firefox","url":"https://e2e.example","desktop":"/tmp/E2EApp.desktop"}]';

late final Directory stubDir;
late final String stubPath;

/// Real Process.run with stub dir prepended to the CHILD's PATH only.
RunFn stubbedRun() {
  return (exe, args) => Process.run(exe, args, environment: {
        ...Platform.environment,
        'PATH': '$stubPath:${Platform.environment['PATH']}',
      });
}

KeyboardEvent charKey(String ch, LogicalKey logical) =>
    KeyboardEvent(logicalKey: logical, character: ch);

/// Real subprocesses need wall-clock time: poll a few rounds.
Future<void> settleReal(NoctermTester t) async {
  for (var i = 0; i < 10; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    await t.pump();
  }
}

void main() {
  setUpAll(() {
    stubDir = Directory.systemTemp.createTempSync('webapp-stubs');
    stubPath = stubDir.path;
    File('$stubPath/webapp-list').writeAsStringSync(
        "#!/usr/bin/env bash\nif [[ \"\$1\" == \"--json\" ]]; then printf '%s' '" +
            _stubListJson +
            "'; else echo \"E2EApp firefox https://e2e.example\"; fi\n");
    File('$stubPath/webapp-create').writeAsStringSync(
        "#!/usr/bin/env bash\necho \"stub-create \$*\" >> \"\$STUB_CALLS\"\necho Created\n");
    File('$stubPath/webapp-remove').writeAsStringSync(
        "#!/usr/bin/env bash\necho \"stub-remove \$*\" >> \"\$STUB_CALLS\"\necho Removed\n");
    File('$stubPath/webapp-doctor').writeAsStringSync(
        "#!/usr/bin/env bash\nif [[ \"\$1\" == \"--json\" ]]; then echo '{\"apps\":[],\"orphans\":[],\"issue_count\":0}'; exit 0; fi\nif [[ \"\$1\" == \"--probe\" ]]; then echo \"  class=E2EApp desktop=E2EApp pid=1 caption=X\"; sleep 0.2; echo \"probe: done\"; fi\n");
    for (final f in stubDir.listSync()) {
      Process.runSync('chmod', ['+x', f.path]);
    }
  });

  tearDownAll(() {
    try {
      stubDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('e2e vs stub toolkit', () {
    test('dashboard renders stub apps via real backend', () async {
      await testNocterm('e2e dashboard', (tester) async {
        await tester.pumpComponent(WebAppTui(
          backend: Backend(run: stubbedRun()),
        ));
        await settleReal(tester);
        expect(tester.terminalState, containsText('E2EApp'));
      });
    });

    test('create submits through real backend to stub', () async {
      final calls = File(
          '${Directory.systemTemp.path}/webapp-e2e-calls-${DateTime.now().millisecondsSinceEpoch}.log');
      Backend backend() => Backend(run: (exe, args) {
            final env = {
              ...Platform.environment,
              'PATH': '$stubPath:${Platform.environment['PATH']}',
              'STUB_CALLS': calls.path,
            };
            return Process.run(exe, args, environment: env);
          });

      await testNocterm('e2e create', (tester) async {
        await tester.pumpComponent(WebAppTui(backend: backend()));
        await tester.pump();
        await tester.sendKeyEvent(charKey('c', LogicalKey.keyC));
        await tester.pump();
        await tester.enterText('E2EMade');
        await tester.pump();
        await tester.sendEnter();
        await tester.pump();
        await tester.enterText('https://made.example');
        await tester.pump();
        await tester.sendEnter();
        await tester.pump();
        await tester.sendEnter(); // engine: default chrome -> icon
        await tester.pump();
        await tester.sendEnter(); // icon empty -> confirm
        await tester.pump();
        await tester.sendEnter(); // confirm -> run
        await settleReal(tester);
      });
      expect(
          calls.readAsStringSync(),
          contains(
              'stub-create --name E2EMade --url https://made.example --engine chrome'));
      calls.deleteSync();
    });

    test('probe streams stub output via real backend', () async {
      await testNocterm('e2e probe', (tester) async {
        final backend = Backend(
          run: stubbedRun(),
          probeStarter: (name) async {
            final proc = await Process.start(
              'webapp-doctor',
              ['--probe', if (name != null) name],
              environment: {
                ...Platform.environment,
                'PATH': '$stubPath:${Platform.environment['PATH']}',
              },
            );
            return ProbeSession.fromProcess(proc);
          },
        );
        await tester.pumpComponent(ProbeScreen(
          backend: backend,
          onBack: () {},
        ));
        await tester.pump();
        await tester.enterText('E2EApp');
        await tester.pump();
        await tester.sendEnter();
        await settleReal(tester);
        expect(tester.terminalState, containsText('class=E2EApp'));
      });
    });
  });
}
