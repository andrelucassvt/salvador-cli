import 'package:get_it/get_it.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/common/services/file_attachment_service.dart';
import 'package:salvador_desktop/common/services/system_memory_service.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';
import 'package:salvador_desktop/data/datasources/git_assistant_datasource.dart';
import 'package:salvador_desktop/data/datasources/git_datasource.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/data/datasources/workspace_datasource.dart';
import 'package:salvador_desktop/data/repositories/chat_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/git_assistant_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/git_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/ollama_repository_impl.dart';
import 'package:salvador_desktop/data/repositories/workspace_repository_impl.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';
import 'package:salvador_desktop/domain/interfaces/git_assistant_repository.dart';
import 'package:salvador_desktop/domain/interfaces/git_repository.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';
import 'package:salvador_desktop/domain/interfaces/workspace_repository.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/file_explorer_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/settings_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/settings_state.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';

/// Service locator unico do app. Populado incrementalmente pelas partes
/// seguintes da migracao (services -> datasources -> repositories -> cubits).
class AppInjector {
  static GetIt inject = GetIt.instance;

  static Future<void> setupDependencies() async {
    // Services
    inject.registerLazySingleton<DesktopStorageService>(
      () => DesktopStorageService(),
    );
    inject.registerLazySingleton<SystemMemoryReader>(
      () => SystemMemoryReader(),
    );
    inject.registerLazySingleton<FileAttachmentService>(
      () => const FileAttachmentService(),
    );
    inject.registerLazySingleton<OllamaDiscovery>(() => OllamaDiscovery());

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
    inject.registerLazySingleton<GitDataSource>(() => GitDataSource());
    inject.registerLazySingleton<GitAssistantDataSource>(
      () => GitAssistantDataSource(),
    );

    // Repositories
    inject.registerLazySingleton<OllamaRepository>(
      () => OllamaRepositoryImpl(
        inject<OllamaRemoteDataSource>(),
        discovery: inject<OllamaDiscovery>(),
      ),
    );
    inject.registerLazySingleton<ChatRepository>(
      () => ChatRepositoryImpl(inject<ChatAgentDataSource>()),
    );
    inject.registerLazySingleton<WorkspaceRepository>(
      () => WorkspaceRepositoryImpl(inject<WorkspaceDataSource>()),
    );
    inject.registerLazySingleton<GitRepository>(
      () => GitRepositoryImpl(inject<GitDataSource>()),
    );
    inject.registerLazySingleton<GitAssistantRepository>(
      () => GitAssistantRepositoryImpl(inject<GitAssistantDataSource>()),
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
      () => ChatCubit(
        inject<ChatRepository>(),
        gitRepository: inject<GitRepository>(),
        attachments: inject<FileAttachmentService>(),
      ),
    );
    inject.registerFactory<FileExplorerCubit>(
      () => FileExplorerCubit(inject<WorkspaceRepository>()),
    );
    inject.registerFactory<GitCubit>(() => GitCubit(inject<GitRepository>()));
    inject.registerFactory<GitAssistantCubit>(
      () => GitAssistantCubit(inject<GitAssistantRepository>()),
    );
    // Recebe o estado inicial do formulario como parametro: depende dos
    // valores atuais do WorkspaceState no momento em que o dialogo abre,
    // que nao existem em tempo de registro.
    inject.registerFactoryParam<SettingsCubit, SettingsEditing, void>(
      (initial, _) =>
          SettingsCubit(inject<OllamaRepository>(), initial: initial),
    );
  }
}
