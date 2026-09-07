/// Root component: screen router + shared key handling.
library;

import 'package:nocterm/nocterm.dart';

import 'backend.dart';
import 'screens/create_form.dart';
import 'screens/dashboard.dart';
import 'screens/doctor_screen.dart';
import 'screens/help_screen.dart';
import 'screens/probe_screen.dart';
import 'screens/remove_screen.dart';

enum AppScreen { dashboard, create, remove, doctor, probe, help }

class WebAppTui extends StatefulComponent {
  final Backend backend;

  WebAppTui({super.key, Backend? backend}) : backend = backend ?? Backend();

  @override
  State<WebAppTui> createState() => _WebAppTuiState();
}

class _WebAppTuiState extends State<WebAppTui> {
  AppScreen screen = AppScreen.dashboard;

  void go(AppScreen next) => setState(() => screen = next);

  @override
  Component build(BuildContext context) {
    final backend = component.backend;
    switch (screen) {
      case AppScreen.dashboard:
        return DashboardScreen(
          backend: backend,
          onOpen: go,
        );
      case AppScreen.create:
        return CreateScreen(
          backend: backend,
          onBack: () => go(AppScreen.dashboard),
        );
      case AppScreen.remove:
        return RemoveScreen(
          backend: backend,
          onBack: () => go(AppScreen.dashboard),
        );
      case AppScreen.doctor:
        return DoctorScreen(
          backend: backend,
          onBack: () => go(AppScreen.dashboard),
        );
      case AppScreen.probe:
        return ProbeScreen(
          backend: backend,
          onBack: () => go(AppScreen.dashboard),
        );
      case AppScreen.help:
        return HelpScreen(onBack: () => go(AppScreen.dashboard));
    }
  }
}
