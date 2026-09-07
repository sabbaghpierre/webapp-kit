import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';
import 'package:webapp_tui/app.dart';
import 'package:webapp_tui/backend.dart';
import 'package:webapp_tui/screens/create_form.dart';
import 'package:webapp_tui/screens/dashboard.dart';
import 'package:webapp_tui/screens/doctor_screen.dart';
import 'package:webapp_tui/screens/probe_screen.dart';
import 'package:webapp_tui/screens/remove_screen.dart';

const _apps = [
  {'name': 'Alpha', 'engine': 'chrome', 'url': 'https://a.example', 'desktop': '/tmp/Alpha.desktop'},
  {'name': 'Beta', 'engine': 'firefox', 'url': 'https://b.example', 'desktop': '/tmp/Beta.desktop'},
];

const _report = {
  'apps': [
    {
      'name': 'Alpha', 'engine': 'chrome', 'url': 'https://a.example',
      'css_version': 'n/a', 'live': false, 'kwin_rule': true, 'issues': []
    },
    {
      'name': 'Bad', 'engine': 'firefox', 'url': 'https://bad.example',
      'css_version': 'v1/v2', 'live': false, 'kwin_rule': false,
      'issues': ['userChrome.css is v1/v2 (hides titlebar); relaunch to migrate']
    }
  ],
  'orphans': <String>[],
  'issue_count': 1,
};

Backend fakeBackend({
  List<String>? seenCreate,
  List<String>? seenRemove,
}) {
  Future<ProcessResult> run(String exe, List<String> args) async {
    if (exe == 'webapp-list') {
      return ProcessResult(0, 0, jsonEncode(_apps), '');
    }
    if (exe == 'webapp-create') {
      seenCreate?.addAll(args);
      return ProcessResult(0, 0, 'Created via stub', '');
    }
    if (exe == 'webapp-remove') {
      seenRemove?.addAll(args);
      return ProcessResult(0, 0, 'Removed via stub', '');
    }
    if (exe == 'webapp-doctor') {
      return ProcessResult(0, 1, jsonEncode(_report), '');
    }
    throw UnimplementedError(exe);
  }

  return Backend(run: run);
}

KeyboardEvent charKey(String ch, LogicalKey logical) =>
    KeyboardEvent(logicalKey: logical, character: ch);

void main() {
  group('dashboard', () {
    test('lists apps and moves highlight', () async {
      await testNocterm('dashboard nav', (tester) async {
        AppScreen? opened;
        await tester.pumpComponent(DashboardScreen(
          backend: fakeBackend(),
          onOpen: (s) => opened = s,
        ));
        await tester.pump();
        expect(tester.terminalState, containsText('webapp-kit dev'));
        expect(tester.terminalState, containsText('Alpha'));
        await tester.pump();
        expect(tester.terminalState, containsText('> Alpha'));
        await tester.sendKey(LogicalKey.arrowDown);
        expect(tester.terminalState, containsText('> Beta'));
        await tester.sendKey(LogicalKey.arrowUp);
        expect(tester.terminalState, containsText('> Alpha'));
        expect(opened, isNull);
      });
    });

    test('c opens create, ? opens help', () async {
      await testNocterm('dashboard shortcuts', (tester) async {
        AppScreen? opened;
        await tester.pumpComponent(DashboardScreen(
          backend: fakeBackend(),
          onOpen: (s) => opened = s,
        ));
        await tester.sendKeyEvent(charKey('c', LogicalKey.keyC));
        expect(opened, AppScreen.create);
      });
    });
  });

  group('create wizard', () {
    test('full flow submits expected flags', () async {
      await testNocterm('create flow', (tester) async {
        final seenCreate = <String>[];
        var backCount = 0;
        await tester.pumpComponent(CreateScreen(
          backend: fakeBackend(seenCreate: seenCreate),
          onBack: () => backCount++,
        ));
        await tester.enterText('MyApp');
        await tester.sendEnter();
        expect(tester.terminalState, containsText('https://example.com'));
        await tester.enterText('https://e.com');
        await tester.sendEnter();
        expect(tester.terminalState, containsText('firefox'));
        // toggle engine to firefox, confirm
        await tester.sendKeyEvent(charKey('e', LogicalKey.keyE));
        await tester.sendEnter();
        expect(tester.terminalState, containsText('auto-fetch'));
        await tester.sendEnter(); // empty icon -> confirm
        expect(tester.terminalState, containsText('Create "MyApp"?'));
        await tester.sendKeyEvent(charKey('y', LogicalKey.keyY));
        await tester.pump();
        expect(
            seenCreate,
            ['--name', 'MyApp', '--url', 'https://e.com', '--engine', 'firefox']);
        expect(tester.terminalState, containsText('Created via stub'));
        expect(backCount, 0);
      });
    });

    test('empty name blocks advance', () async {
      await testNocterm('create validation', (tester) async {
        await tester.pumpComponent(CreateScreen(
          backend: fakeBackend(),
          onBack: () {},
        ));
        await tester.sendEnter();
        expect(tester.terminalState, containsText('Name is required'));
      });
    });
  });

  group('remove screen', () {
    test('toggle two apps and delete keeping data', () async {
      await testNocterm('remove flow', (tester) async {
        final seenRemove = <String>[];
        await tester.pumpComponent(RemoveScreen(
          backend: fakeBackend(seenRemove: seenRemove),
          onBack: () {},
        ));
        await tester.pump();
        expect(tester.terminalState, containsText('Alpha'));
        await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.space, character: ' '));
        await tester.sendKey(LogicalKey.arrowDown);
        await tester.sendKeyEvent(KeyboardEvent(
            logicalKey: LogicalKey.space, character: ' '));
        await tester.sendKeyEvent(charKey('y', LogicalKey.keyY));
        await tester.pump();
        expect(tester.terminalState, containsText('PURGE'));
        await tester.sendKeyEvent(charKey('y', LogicalKey.keyY));
        await tester.pump();
        expect(seenRemove, ['Alpha', 'Beta']);
        expect(tester.terminalState, containsText('Removed via stub'));
      });
    });
  });

  group('doctor screen', () {
    test('renders ok and warnings', () async {
      await testNocterm('doctor rows', (tester) async {
        await tester.pumpComponent(DoctorScreen(
          backend: fakeBackend(),
          onBack: () {},
        ));
        await tester.pump();
        expect(tester.terminalState, containsText('ok Alpha'));
        await tester.pump();
        expect(tester.terminalState, containsText('WARN Bad'));
        await tester.pump();
        expect(tester.terminalState, containsText('v1/v2'));
      });
    });
  });

  group('probe screen', () {
    test('streams samples and highlights match', () async {
      await testNocterm('probe stream', (tester) async {
        final backend = Backend(
          run: (exe, args) async => ProcessResult(0, 0, '[]', ''),
          probeStarter: (_) async => ProbeSession(
            stdout: Stream.fromIterable([
              utf8.encode('  [ 1s] class=Beta desktop=Beta pid=42 caption=Hi\n'),
              utf8.encode("probe: MATCH — done\n"),
            ]),
            exitCode: Future.value(0),
            onStop: () async {},
          ),
        );
        await tester.pumpComponent(ProbeScreen(
          backend: backend,
          onBack: () {},
        ));
        await tester.enterText('Beta');
        await tester.sendEnter();
        await tester.pump();
        expect(tester.terminalState, containsText('MATCH'));
        await tester.pump();
        expect(tester.terminalState, containsText('class=Beta'));
      });
    });
  });
}
