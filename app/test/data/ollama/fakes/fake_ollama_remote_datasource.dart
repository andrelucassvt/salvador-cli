import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';

class FakeOllamaRemoteDataSource implements OllamaRemoteDataSource {
  Object? exceptionToThrow;

  /// Quantas chamadas lanca [exceptionToThrow] antes de responder
  /// normalmente. null (padrao) = lanca sempre.
  int? failCount;
  List<OllamaModelInfo> models = const [];
  List<OllamaRunningModel> runningModels = const [];
  int? modelContext;

  void _maybeThrow() {
    final error = exceptionToThrow;
    if (error == null) return;
    if (failCount == null || failCount! > 0) {
      if (failCount != null) failCount = failCount! - 1;
      throw error;
    }
  }

  @override
  Future<void> testConnection(Uri host) async {
    _maybeThrow();
  }

  @override
  Future<List<OllamaModelInfo>> listModels(Uri host) async {
    _maybeThrow();
    return models;
  }

  @override
  Future<List<OllamaRunningModel>> listRunningModels(
    Uri host,
    List<OllamaModelInfo> installed,
  ) async {
    _maybeThrow();
    return runningModels;
  }

  @override
  Future<void> loadModel(Uri host, String model, Duration keepAlive) async {
    _maybeThrow();
  }

  @override
  Future<void> unloadModel(Uri host, String model) async {
    _maybeThrow();
  }

  @override
  Future<int?> showModelContext(Uri host, String model) async {
    _maybeThrow();
    return modelContext;
  }
}
