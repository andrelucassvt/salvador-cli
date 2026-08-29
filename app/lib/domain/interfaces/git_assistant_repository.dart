import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

/// Sessao dedicada do assistente Git: ferramentas Git estruturadas, sem
/// `run_command`, com contexto limitado por chamada e propostas tipadas.
abstract interface class GitAssistantRepository {
  Stream<ToolActivityEntity> get toolActivity;

  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  });

  Future<Result<AgentTurnResult>> send({
    required String input,
    String? context,
  });

  void clearSession();
}
