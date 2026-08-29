import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

/// Encapsula `AgentSession` (pacote `salvador_cli`), que e stateful: mantem
/// o historico da conversa internamente e expoe um callback sincrono de
/// atividade de ferramenta, adaptado aqui para um stream broadcast.
class ChatAgentDataSource {
  ChatAgentDataSource({OllamaClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final OllamaClientFactory _clientFactory;
  final StreamController<ToolActivityEntity> _activityController =
      StreamController<ToolActivityEntity>.broadcast();

  AgentSession? _session;
  ContextFilesService? _contextFiles;

  Stream<ToolActivityEntity> get toolActivity => _activityController.stream;

  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
    required bool contextFilesEnabled,
  }) {
    final client = _clientFactory(
      model: model,
      baseUrl: host,
      options: options,
    );
    _contextFiles = root != null && contextFilesEnabled
        ? ContextFilesService(root)
        : null;
    _session = AgentSession(
      client: client,
      root: root,
      permissions: permissions,
      contextFiles: _contextFiles,
      gitClient: root == null ? null : GitClient(),
      gitProfile: root == null
          ? null
          : const GitProfile(replacesRunCommand: false),
      onToolResult: (call, result) {
        _activityController.add(ToolActivityEntity(call: call, result: result));
      },
    );
  }

  Future<AgentTurnResult> send(
    String message, {
    List<String> images = const [],
  }) async {
    final session = _session;
    if (session == null) {
      throw const AgentException('sessao do agente nao configurada');
    }
    final expansion = message.startsWith('/') && _contextFiles != null
        ? _contextFiles!.expand(message)
        : MentionExpansion(prompt: message);
    final result = await session.sendDetailed(expansion.prompt, images: images);
    return AgentTurnResult(
      answer: result.answer,
      metrics: result.metrics,
      mentionedFiles: result.mentionedFiles,
      warnings: [...expansion.warnings, ...result.warnings],
      proposals: result.proposals,
    );
  }

  void clearSession() => _session?.clear();

  Future<void> dispose() => _activityController.close();

  static OllamaClient _defaultClientFactory({
    required String model,
    required Uri baseUrl,
    required InferenceOptions options,
  }) => OllamaClient(model: model, baseUrl: baseUrl, options: options);
}
