import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/domain/interfaces/git_assistant_repository.dart';

class FakeGitAssistantRepository implements GitAssistantRepository {
  final List<String> sentInputs = [];
  String? lastContext;
  Result<AgentTurnResult>? nextResult;
  int configureCalls = 0;
  int clearCalls = 0;
  final StreamController<ToolActivityEntity> _activities =
      StreamController<ToolActivityEntity>.broadcast();

  @override
  Stream<ToolActivityEntity> get toolActivity => _activities.stream;

  @override
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  }) {
    configureCalls++;
  }

  @override
  Future<Result<AgentTurnResult>> send({
    required String input,
    String? context,
  }) async {
    sentInputs.add(input);
    lastContext = context;
    final queued = nextResult;
    nextResult = null;
    if (queued != null) return queued;
    return const Result.ok(
      AgentTurnResult(
        answer: 'resposta fake',
        proposals: [GitActionProposal(type: GitActionType.fetch)],
      ),
    );
  }

  @override
  void clearSession() => clearCalls++;

  void emitActivity(ToolActivityEntity activity) => _activities.add(activity);
}
