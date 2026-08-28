import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';

class OllamaRepositoryImpl implements OllamaRepository {
  const OllamaRepositoryImpl(this._dataSource);

  final OllamaRemoteDataSource _dataSource;

  @override
  Future<Result<void>> testConnection({required Uri host}) async {
    try {
      await _dataSource.testConnection(host);
      return const Result.ok(null);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<List<OllamaModelInfo>>> listModels({required Uri host}) async {
    try {
      final models = await _dataSource.listModels(host);
      if (models.isEmpty) {
        return const Result.error(
          OllamaServerException(
            'Nenhum modelo instalado. Execute ollama pull <modelo>.',
          ),
        );
      }
      return Result.ok(models);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<List<OllamaRunningModel>>> listRunningModels({
    required Uri host,
    required List<OllamaModelInfo> installed,
  }) async {
    try {
      final running = await _dataSource.listRunningModels(host, installed);
      return Result.ok(running);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<void>> loadModel({
    required Uri host,
    required String model,
    required Duration keepAlive,
  }) async {
    try {
      await _dataSource.loadModel(host, model, keepAlive);
      return const Result.ok(null);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<void>> unloadModel({
    required Uri host,
    required String model,
  }) async {
    try {
      await _dataSource.unloadModel(host, model);
      return const Result.ok(null);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<int?>> showModelContext({
    required Uri host,
    required String model,
  }) async {
    try {
      final context = await _dataSource.showModelContext(host, model);
      return Result.ok(context);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  AppException _toAppException(Object error, StackTrace stackTrace) {
    if (error is AppException) return error;
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
