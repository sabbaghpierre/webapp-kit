/// Static help overlay mirroring `webapp-help`.
library;

import 'package:nocterm/nocterm.dart';

class HelpScreen extends StatelessComponent {
  final VoidCallback onBack;

  const HelpScreen({super.key, required this.onBack});

  @override
  Component build(BuildContext context) {
    const lines = [
      'webapp-kit help',
      '',
      'Dashboard keys:',
      '  up/down or j/k .. move selection',
      '  c ................ create a webapp',
      '  x ................ remove webapp(s)',
      '  d / Enter ........ doctor (health check)',
      '  p ................ probe live window identity',
      '  r ................ refresh list',
      '  q ................ quit',
      '',
      'Each webapp is isolated: own Chrome data dir or Firefox',
      'profile (log in once inside the webapp window).',
      '',
      'CLI equivalents: webapp-create, webapp-remove --purge,',
      'webapp-list, webapp-doctor [--probe NAME] [--deps].',
      '',
      'Press Esc to go back.',
    ];
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape) {
          onBack();
          return true;
        }
        return false;
      },
      child: Container(
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines) Text(line),
          ],
        ),
      ),
    );
  }
}
