import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

class FakeChatAgentDataSource implements ChatAgentDataSource {
  final StreamController<ToolActivityEntity> activityController =
      StreamController<ToolActivityEntity>.broadcast();

  Object? exceptionToThrow;
  AgentTurnResult reply = const AgentTurnResult(answer: 'ok');
  int configureCallCount = 0;
  int clearCallCount = 0;
  String? lastMessage;
  List<String>? lastImages;

  @override
  Stream<ToolActivityEntity> get toolActivity => activityController.stream;

  @override
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  }) {
    configureCallCount++;
  }

  @override
  Future<AgentTurnResult> send(
    String message, {
    List<String> images = const [],
  }) async {
    lastMessage = message;
    lastImages = images;
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return reply;
  }

  @override
  void clearSession() {
    clearCallCount++;
  }

  @override
  Future<void> dispose() => activityController.close();
}
