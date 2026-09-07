import 'dart:io';

import 'package:test/test.dart';
import 'package:webapp_tui/backend.dart';
import 'package:webapp_tui/models.dart';

const _listJson = '''
[{"name":"WhatsApp","engine":"chrome","url":"https://web.whatsapp.com","desktop":"/home/u/.local/share/applications/WhatsApp.desktop"},
 {"name":"Weird \\"Q\\" App","engine":"custom","url":"(custom exec)","desktop":"/home/u/.local/share/applications/Weird \\"Q\\" App.desktop"}]
''';

const _doctorJson = '''
{"apps":[{"name":"Strafe","engine":"firefox","url":"https://strafe.com","desktop":"/home/u/.local/share/applications/Strafe.desktop","icon":"Strafe","icon_path":"/home/u/.local/share/icons/hicolor/128x128/apps/Strafe.png","startup_wmclass":"Strafe","desktop_valid":true,"profile_dir":"/home/u/.local/share/webapps/firefox-Strafe","css_version":"v3","kwin_rule":true,"live":false,"log_tail":"","issues":[]},
{"name":"Bad App","engine":"firefox","url":"https://bad.example","desktop":"/home/u/.local/share/applications/Bad App.desktop","icon":"/nonexistent/icon.png","icon_path":"/nonexistent/icon.png","startup_wmclass":"","desktop_valid":null,"profile_dir":"","css_version":"n/a","kwin_rule":false,"live":false,"log_tail":"","issues":["icon missing: /nonexistent/icon.png","no KWin rule"]}],
"orphans":["/home/u/.local/share/webapps/firefox-Orphaned"],"issue_count":2}
''';

void main() {
  group('parseAppList', () {
    test('parses apps incl. quoted names', () {
      final apps = parseAppList(_listJson);
      expect(apps, hasLength(2));
      expect(apps[0].name, 'WhatsApp');
      expect(apps[0]. engine, 'chrome');
      expect(apps[1].name, 'Weird "Q" App');
    });

    test('empty array', () {
      expect(parseAppList('[]'), isEmpty);
    });

    test('invalid json throws', () {
      expect(() => parseAppList('nope'), throwsFormatException);
      expect(() => parseAppList('{}'), throwsFormatException);
    });
  });

  group('parseDoctorReport', () {
    test('apps, issues, orphans', () {
      final report = parseDoctorReport(_doctorJson);
      expect(report.apps, hasLength(2));
      expect(report.apps[0].healthy, isTrue);
      expect(report.apps[0].cssVersion, 'v3');
      expect(report.apps[1].healthy, isFalse);
      expect(report.apps[1].issues, hasLength(2));
      expect(report.orphans, ['/home/u/.local/share/webapps/firefox-Orphaned']);
      expect(report.issueCount, 2);
    });

    test('tolerates missing keys', () {
      final report = parseDoctorReport('{"apps":[{}],"orphans":[]}');
      expect(report.apps.single.name, '');
      expect(report.apps.single.healthy, isTrue);
    });

    test('invalid json throws', () {
      expect(() => parseDoctorReport('[]'), throwsFormatException);
      expect(() => parseDoctorReport('garbage'), throwsFormatException);
    });
  });

  group('parseProbeLine', () {
    test('kwin sample', () {
      final s = parseProbeLine(
          '  [ 1s] class=Strafe                 desktop=Strafe                 pid=12480    caption=Strafe Esports | Watch |');
      expect(s.klass, 'Strafe');
      expect(s.desktop, 'Strafe');
      expect(s.pid, '12480');
      expect(s.title, contains('Esports'));
    });

    test('niri/hypr sample without desktop', () {
      final s = parseProbeLine('  class=firefox                pid=111      title=Mozilla Firefox');
      expect(s.klass, 'firefox');
      expect(s.desktop, isNull);
      expect(s.title, 'Mozilla Firefox');
    });

    test('MATCH and prompt lines pass through raw', () {
      final s = parseProbeLine("probe: MATCH — window reports class 'Strafe'");
      expect(s.klass, isNull);
      expect(s.raw, contains('MATCH'));
    });
  });

  group('Backend', () {
    Future<ProcessResult> fakeRun(String exe, List<String> args) async {
      if (exe == 'webapp-list') return ProcessResult(0, 0, _listJson, '');
      if (exe == 'webapp-create') return ProcessResult(0, 0, 'Created X', '');
      if (exe == 'webapp-remove') return ProcessResult(0, 1, '', 'boom');
      if (exe == 'webapp-doctor') return ProcessResult(0, 1, _doctorJson, '');
      throw UnimplementedError(exe);
    }

    test('listApps maps json', () async {
      final apps = await Backend(run: fakeRun).listApps();
      expect(apps.map((a) => a.name), ['WhatsApp', 'Weird "Q" App']);
    });

    test('createApp passes flags, ok on exit 0', () async {
      String? seenExe;
      List<String>? seenArgs;
      final b = Backend(run: (exe, args) async {
        seenExe = exe;
        seenArgs = args;
        return ProcessResult(0, 0, 'ok', '');
      });
      final r = await b.createApp(
          name: 'N', url: 'https://e.com', engine: 'firefox', icon: '');
      expect(seenExe, 'webapp-create');
      expect(seenArgs,
          ['--name', 'N', '--url', 'https://e.com', '--engine', 'firefox']);
      expect(r.ok, isTrue);
    });

    test('createApp with icon appends --icon', () async {
      List<String>? seenArgs;
      final b = Backend(run: (exe, args) async {
        seenArgs = args;
        return ProcessResult(0, 0, '', '');
      });
      await b.createApp(
          name: 'N', url: 'https://e.com', engine: 'chrome', icon: '/tmp/i.png');
      expect(seenArgs!.last, '/tmp/i.png');
      expect(seenArgs, contains('--icon'));
    });

    test('removeApps ok reflects exit code', () async {
      final b = Backend(run: fakeRun);
      expect((await b.removeApps(['A'], purge: true)).ok, isFalse);
    });

    test('doctor parses despite exit 1', () async {
      final report = await Backend(run: fakeRun).doctor();
      expect(report.apps, hasLength(2));
      expect(report.issueCount, 2);
    });

    test('missing binary becomes BackendException', () async {
      final b = Backend(run: (exe, args) async {
        throw const ProcessException('webapp-list', []);
      });
      expect(() => b.listApps(), throwsA(isA<BackendException>()));
    });
  });
}
