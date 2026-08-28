import 'package:get_it/get_it.dart';

/// Service locator unico do app. Populado incrementalmente pelas partes
/// seguintes da migracao (services -> datasources -> repositories -> cubits).
class AppInjector {
  static GetIt inject = GetIt.instance;

  static Future<void> setupDependencies() async {}
}
