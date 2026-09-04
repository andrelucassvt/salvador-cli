import 'dart:async';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';

class FakeChatRepository implements ChatRepository {
  final StreamController<ToolActivityEntity> activityController =
      StreamController<ToolActivityEntity>.broadcast();

  AppException? failure;
  AgentTurnResult reply = const AgentTurnResult(answer: 'ok');
  int configureCallCount = 0;
  int clearCallCount = 0;
  String? lastMessage;
  List<String>? lastImages;
  Directory? lastRoot;
  bool? lastContextFilesEnabled;

  @override
  Stream<ToolActivityEntity> get toolActivity => activityController.stream;

  @override
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
    required bool contextFilesEnabled,
  }) {
    configureCallCount++;
    lastRoot = root;
    lastContextFilesEnabled = contextFilesEnabled;
  }

  @override
  Future<Result<AgentTurnResult>> send(
    String message, {
    List<String> images = const [],
  }) async {
    lastMessage = message;
    lastImages = images;
    if (failure != null) return Result.error(failure!);
    return Result.ok(reply);
  }

  @override
  void clearSession() {
    clearCallCount++;
  }
}
