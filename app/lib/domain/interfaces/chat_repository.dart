import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

/// Foge do molde stateless dos demais repositories: `AgentSession` (pacote
/// `salvador_cli`) mantem historico da conversa internamente, entao a sessao
/// e configurada uma vez e reaproveitada entre envios, em vez de cada metodo
/// ser uma chamada isolada.
abstract class ChatRepository {
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  });

  Stream<ToolActivityEntity> get toolActivity;

  Future<Result<AgentTurnResult>> send(String message);

  void clearSession();
}
