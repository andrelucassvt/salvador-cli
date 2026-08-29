import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/result_pattern.dart';

abstract class OllamaRepository {
  Future<Result<void>> testConnection({required Uri host});

  Future<Result<List<OllamaModelInfo>>> listModels({required Uri host});

  Future<Result<List<OllamaRunningModel>>> listRunningModels({
    required Uri host,
    required List<OllamaModelInfo> installed,
  });

  Future<Result<void>> loadModel({
    required Uri host,
    required String model,
    required Duration keepAlive,
  });

  Future<Result<void>> unloadModel({required Uri host, required String model});

  Future<Result<int?>> showModelContext({
    required Uri host,
    required String model,
  });
}
