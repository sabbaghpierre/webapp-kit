/// Subprocess bridge to the webapp-* CLI toolkit.
/// The TUI never reimplements toolkit logic: every read goes through
/// --json, every mutation through the scripts' non-interactive flags.
/// The command runner is injectable so tests can fake the toolkit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Injectable command runner (defaults to [Process.run]).
typedef RunFn = Future<ProcessResult> Function(String exe, List<String> args);

/// Injectable probe starter (defaults to spawning the real CLI).
typedef ProbeStarter = Future<ProbeSession> Function(String? name);

Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
    Process.run(exe, args);

class BackendException implements Exception {
  final String message;
  const BackendException(this.message);

  @override
  String toString() => 'BackendException: $message';
}

class CommandResult {
  final bool ok;
  final String output;
  const CommandResult({required this.ok, required this.output});
}

class Backend {
  final RunFn run;
  final ProbeStarter probeStarter;

  Backend({RunFn? run, ProbeStarter? probeStarter})
      : run = run ?? _defaultRun,
        probeStarter = probeStarter ?? _defaultProbeStarter;

  /// Run a toolkit command, mapping "binary missing" to a helpful error.
  Future<ProcessResult> _guarded(String exe, List<String> args) async {
    try {
      return await run(exe, args);
    } on ProcessException catch (e) {
      throw BackendException(
          '$exe not found on PATH. Install webapp-kit first:\n'
          '  curl -fsSL https://raw.githubusercontent.com/sabbaghpierre/webapp-kit/main/install.sh | bash\n'
          '($e)');
    }
  }

  String _text(ProcessResult r) => '${r.stdout}${r.stderr}';

  Future<List<WebApp>> listApps() async {
    final r = await _guarded('webapp-list', const ['--json']);
    if (r.exitCode != 0) {
      throw BackendException('webapp-list failed:\n${_text(r)}');
    }
    try {
      return parseAppList(r.stdout as String);
    } on FormatException catch (e) {
      throw BackendException('could not parse webapp-list output: $e');
    }
  }

  Future<CommandResult> createApp({
    required String name,
    required String url,
    required String engine,
    String? icon,
  }) async {
    final args = ['--name', name, '--url', url, '--engine', engine];
    if (icon != null && icon.trim().isNotEmpty) {
      args.addAll(['--icon', icon.trim()]);
    }
    final r = await _guarded('webapp-create', args);
    return CommandResult(ok: r.exitCode == 0, output: _text(r));
  }

  Future<CommandResult> removeApps(List<String> names,
      {bool purge = false}) async {
    final args = <String>[if (purge) '--purge', ...names];
    final r = await _guarded('webapp-remove', args);
    return CommandResult(ok: r.exitCode == 0, output: _text(r));
  }

  /// doctor exit code 1 on warnings is NORMAL — parse stdout regardless.
  Future<DoctorReport> doctor([String? name]) async {
    final r = await _guarded(
        'webapp-doctor', ['--json', if (name != null) name]);
    try {
      return parseDoctorReport(r.stdout as String);
    } on FormatException {
      throw BackendException('could not parse webapp-doctor output:\n${_text(r)}');
    }
  }

  /// Start a streaming probe (`webapp-doctor --probe`). Lines arrive on the
  /// returned subscription; caller must cancel + kill (see [ProbeSession.stop]).
  Future<ProbeSession> startProbe(String? name) => probeStarter(name);
}

/// Default probe starter: spawns the real CLI.
Future<ProbeSession> _defaultProbeStarter(String? name) async {
  Process proc;
  try {
    proc = await Process.start(
        'webapp-doctor', ['--probe', if (name != null) name]);
  } on ProcessException catch (e) {
    throw BackendException('could not start probe: $e');
  }
  return ProbeSession.fromProcess(proc);
}

/// A live `webapp-doctor --probe` process with line-streamed stdout.
class ProbeSession {
  final Stream<List<int>> _out;
  final Future<int> _exitCode;
  final Future<void> Function() _onStop;
  bool _stopped = false;

  ProbeSession({
    required Stream<List<int>> stdout,
    required Future<int> exitCode,
    required Future<void> Function() onStop,
  })  : _out = stdout,
        _exitCode = exitCode,
        _onStop = onStop;

  factory ProbeSession.fromProcess(Process proc) => ProbeSession(
        stdout: proc.stdout,
        exitCode: proc.exitCode,
        onStop: () async {
          proc.kill(ProcessSignal.sigterm);
          try {
            await proc.exitCode.timeout(const Duration(seconds: 2));
          } catch (_) {
            proc.kill(ProcessSignal.sigkill);
          }
        },
      );

  Stream<ProbeSample> get lines => _out
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map(parseProbeLine);

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _onStop();
    try {
      await _exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
