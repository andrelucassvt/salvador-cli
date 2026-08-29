import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

/// Sessao dedicada do assistente Git: `AgentSession` proprio com perfil Git,
/// `allowCommands: false`, contexto serializado por envio e stream de
/// atividades de ferramenta.
class GitAssistantDataSource {
  GitAssistantDataSource({OllamaClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final OllamaClientFactory _clientFactory;
  final StreamController<ToolActivityEntity> _activityController =
      StreamController<ToolActivityEntity>.broadcast();

  AgentSession? _session;

  Stream<ToolActivityEntity> get toolActivity => _activityController.stream;

  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  }) {
    final client = _clientFactory(
      model: model,
      baseUrl: host,
      options: options,
    );
    _session = AgentSession(
      client: client,
      root: root,
      permissions: AgentPermissions(
        allowEdit: permissions.allowEdit,
        allowCommands: false,
      ),
      gitClient: GitClient(),
      gitProfile: const GitProfile(),
      onToolResult: (call, result) {
        _activityController.add(ToolActivityEntity(call: call, result: result));
      },
    );
  }

  Future<AgentTurnResult> send({required String input, String? context}) async {
    final session = _session;
    if (session == null) {
      throw const AgentException('sessao do assistente Git nao configurada');
    }
    final prompt = (context == null || context.isEmpty)
        ? input
        : '$context\n\n$input';
    return session.sendDetailed(prompt);
  }

  void clearSession() => _session?.clear();

  Future<void> dispose() => _activityController.close();

  static OllamaClient _defaultClientFactory({
    required String model,
    required Uri baseUrl,
    required InferenceOptions options,
  }) => OllamaClient(model: model, baseUrl: baseUrl, options: options);
}
