import 'dart:io';

import 'package:flutter/material.dart';
import 'package:salvador_desktop/config/inject/app_injector.dart';
import 'package:salvador_desktop/src/desktop/salvador_desktop_app.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppInjector.setupDependencies();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(titleBarStyle: TitleBarStyle.hidden);
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const SalvadorDesktopApp());
}
