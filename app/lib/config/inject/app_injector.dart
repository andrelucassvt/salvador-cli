import 'package:get_it/get_it.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/data/repositories/ollama_repository_impl.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';

/// Service locator unico do app. Populado incrementalmente pelas partes
/// seguintes da migracao (services -> datasources -> repositories -> cubits).
class AppInjector {
  static GetIt inject = GetIt.instance;

  static Future<void> setupDependencies() async {
    // Services
    inject.registerLazySingleton<DesktopStorageService>(
      () => DesktopStorageService(),
    );
    inject.registerLazySingleton<SystemMemoryReader>(() => SystemMemoryReader());

    // DataSources
    inject.registerLazySingleton<OllamaRemoteDataSource>(
      () => OllamaRemoteDataSource(),
    );

    // Repositories
    inject.registerLazySingleton<OllamaRepository>(
      () => OllamaRepositoryImpl(inject<OllamaRemoteDataSource>()),
    );

    // Cubits (sempre Factory)
    inject.registerFactory<WorkspaceCubit>(
      () => WorkspaceCubit(
        inject<OllamaRepository>(),
        inject<DesktopStorageService>(),
        memoryReader: inject<SystemMemoryReader>(),
      ),
    );
  }
}
