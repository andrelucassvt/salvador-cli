import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/data/datasources/ollama_remote_datasource.dart';

class FakeOllamaRemoteDataSource implements OllamaRemoteDataSource {
  Object? exceptionToThrow;
  List<OllamaModelInfo> models = const [];
  List<OllamaRunningModel> runningModels = const [];
  int? modelContext;

  @override
  Future<void> testConnection(Uri host) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
  }

  @override
  Future<List<OllamaModelInfo>> listModels(Uri host) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return models;
  }

  @override
  Future<List<OllamaRunningModel>> listRunningModels(
    Uri host,
    List<OllamaModelInfo> installed,
  ) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return runningModels;
  }

  @override
  Future<void> loadModel(Uri host, String model, Duration keepAlive) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
  }

  @override
  Future<void> unloadModel(Uri host, String model) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
  }

  @override
  Future<int?> showModelContext(Uri host, String model) async {
    if (exceptionToThrow != null) throw exceptionToThrow!;
    return modelContext;
  }
}
