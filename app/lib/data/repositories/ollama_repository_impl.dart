import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';

class OllamaRepositoryImpl implements OllamaRepository {
  OllamaRepositoryImpl(this._dataSource, {OllamaDiscovery? discovery})
    : _discovery = discovery ?? OllamaDiscovery();

  static const _localHosts = {'127.0.0.1', 'localhost', '::1'};

  final OllamaRemoteDataSource _dataSource;
  final OllamaDiscovery _discovery;

  @override
  Future<Result<void>> testConnection({required Uri host}) async {
    try {
      await _withAutoBoot(host, () => _dataSource.testConnection(host));
      return const Result.ok(null);
    } catch (error, stackTrace) {
      return Result.error(_toAppException(error, stackTrace));
    }
  }

  @override
  Future<Result<List<OllamaModelInfo>>> listModels({required Uri host}) async {
    try {
      final models = await _withAutoBoot(
        host,
        () => _dataSource.listModels(host),
      );
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

  /// Quando o servidor HTTP nao responde (conexao recusada) e o host e
  /// local, o binario `ollama` consegue reabrir o servidor em background:
  /// roda `ollama list` (o mesmo comando usado manualmente no terminal) e
  /// retenta a operacao uma vez. Servidor fora do ar no meio do app nao
  /// passa por aqui - so as chamadas de conexao/lista de modelos.
  Future<T> _withAutoBoot<T>(Uri host, Future<T> Function() operation) async {
    try {
      return await operation();
    } on SocketException {
      if (!_localHosts.contains(host.host)) rethrow;
      if (!await _boot()) rethrow;
      return await operation();
    }
  }

  Future<bool> _boot() async {
    try {
      await _discovery.listModels();
      return true;
    } on OllamaDiscoveryException {
      // Binario ausente ou servidor nao subiu: mantem o erro original.
      return false;
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
