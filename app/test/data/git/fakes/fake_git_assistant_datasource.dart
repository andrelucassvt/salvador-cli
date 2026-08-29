import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/git_assistant_datasource.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

class FakeGitAssistantDataSource implements GitAssistantDataSource {
  final List<String> configuredModels = [];
  final List<String?> configuredRoots = [];
  final List<(String, String?)> sentInputs = [];
  Object? errorToThrow;
  AgentTurnResult? resultToReturn;
  int clearCalls = 0;
  final StreamController<ToolActivityEntity> activities =
      StreamController<ToolActivityEntity>.broadcast();

  @override
  Stream<ToolActivityEntity> get toolActivity => activities.stream;

  @override
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  }) {
    configuredModels.add(model);
    configuredRoots.add(root?.path);
  }

  @override
  Future<AgentTurnResult> send({required String input, String? context}) async {
    sentInputs.add((input, context));
    if (errorToThrow != null) throw errorToThrow!;
    return resultToReturn ??
        AgentTurnResult(
          answer: 'resposta do assistente Git',
          proposals: const [GitActionProposal(type: GitActionType.fetch)],
        );
  }

  @override
  void clearSession() => clearCalls++;

  @override
  Future<void> dispose() => activities.close();
}
