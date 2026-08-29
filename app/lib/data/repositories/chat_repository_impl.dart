import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/data/datasources/chat_agent_datasource.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/domain/interfaces/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  const ChatRepositoryImpl(this._dataSource);

  final ChatAgentDataSource _dataSource;

  @override
  Stream<ToolActivityEntity> get toolActivity => _dataSource.toolActivity;

  @override
  void configureSession({
    required Uri host,
    required String model,
    required InferenceOptions options,
    required Directory? root,
    required AgentPermissions permissions,
  }) {
    _dataSource.configureSession(
      host: host,
      model: model,
      options: options,
      root: root,
      permissions: permissions,
    );
  }

  @override
  Future<Result<AgentTurnResult>> send(String message) async {
    try {
      final reply = await _dataSource.send(message);
      return Result.ok(reply);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  void clearSession() => _dataSource.clearSession();

  AppException _toAppException(Object error, StackTrace stackTrace) {
    if (error is AppException) return error;
    if (error is AgentException) {
      return AgentFailureException(
        'Erro do agente: ${error.message}',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is SocketException) {
      return NetworkException(
        'Não foi possível conectar ao Ollama: ${error.message}',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is OllamaException) {
      return OllamaServerException(
        error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return UnknownException(
      'Falha inesperada',
      cause: error,
      stackTrace: stackTrace,
    );
  }
}
