import 'package:get_it/get_it.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/data/datasources/workspace_datasource.dart';
import 'package:salvador_desktop/data/repositories/chat_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/ollama_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/workspace_repository_impl.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/domain/interfaces/workspace_repository.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_cubit.dart';
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
    inject.registerLazySingleton<ChatAgentDataSource>(
      () => ChatAgentDataSource(),
    );
    inject.registerLazySingleton<WorkspaceDataSource>(
      () => WorkspaceDataSource(),
    );

    // Repositories
    inject.registerLazySingleton<OllamaRepository>(
      () => OllamaRepositoryImpl(inject<OllamaRemoteDataSource>()),
    );
    inject.registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImpl(inject<ChatAgentDataSource>()),
    );
    inject.registerLazySingleton<WorkspaceRepository>(
      () => WorkspaceRepositoryImpl(inject<WorkspaceDataSource>()),
    );

    // Cubits (sempre Factory)
    inject.registerFactory<WorkspaceCubit>(
      () => WorkspaceCubit(
        inject<OllamaRepository>(),
        inject<DesktopStorageService>(),
        memoryReader: inject<SystemMemoryReader>(),
      ),
    );
    inject.registerFactory<ChatCubit>(
      () => ChatCubit(inject<ChatRepository>()),
    );
    inject.registerFactory<FileExplorerCubit>(
      () => FileExplorerCubit(inject<WorkspaceRepository>()),
    );
  }
}
