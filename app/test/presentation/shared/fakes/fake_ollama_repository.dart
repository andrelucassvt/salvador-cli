import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';
import 'package:salvador_desktop/domain/interfaces/ollama_repository.dart';

class FakeOllamaRepository implements OllamaRepository {
  /// Falha a ser devolvida; `null` = caminho feliz.
  AppException? failure;
  List<OllamaModelInfo> models = const [];
  List<OllamaRunningModel> runningModels = const [];
  int? modelContext;
  int loadModelCallCount = 0;
  int unloadModelCallCount = 0;

  @override
  Future<Result<void>> testConnection({required Uri host}) async {
    if (failure != null) return Result.error(failure!);
    return const Result.ok(null);
  }

  @override
  Future<Result<List<OllamaModelInfo>>> listModels({required Uri host}) async {
    if (failure != null) return Result.error(failure!);
    if (models.isEmpty) {
      return const Result.error(
        OllamaServerException('Nenhum modelo instalado.'),
      );
    }
    return Result.ok(models);
  }

  @override
  Future<Result<List<OllamaRunningModel>>> listRunningModels({
    required Uri host,
    required List<OllamaModelInfo> installed,
  }) async {
    if (failure != null) return Result.error(failure!);
    return Result.ok(runningModels);
  }

  @override
  Future<Result<void>> loadModel({
    required Uri host,
    required String model,
    required Duration keepAlive,
  }) async {
    loadModelCallCount++;
    if (failure != null) return Result.error(failure!);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> unloadModel({
    required Uri host,
    required String model,
  }) async {
    unloadModelCallCount++;
    if (failure != null) return Result.error(failure!);
    return const Result.ok(null);
  }

  @override
  Future<Result<int?>> showModelContext({
    required Uri host,
    required String model,
  }) async {
    if (failure != null) return Result.error(failure!);
    return Result.ok(modelContext);
  }
}
