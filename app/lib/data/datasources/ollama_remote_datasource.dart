import 'package:salvador_cli/salvador_cli.dart';

typedef OllamaClientFactory =
    OllamaClient Function({
      required String model,
      required Uri baseUrl,
      required InferenceOptions options,
    });

/// Encapsula a criacao de `OllamaClient` (pacote `salvador_cli`), que amarra
/// modelo/host/opcoes no construtor em vez de recebe-los por chamada.
class OllamaRemoteDataSource {
  OllamaRemoteDataSource({OllamaClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final OllamaClientFactory _clientFactory;

  Future<void> testConnection(Uri host) => _client(host).testConnection();

  Future<List<OllamaModelInfo>> listModels(Uri host) =>
      _client(host).listModels();

  Future<List<OllamaRunningModel>> listRunningModels(
    Uri host,
    List<OllamaModelInfo> installed,
  ) => _client(host).listRunningModels(installed: installed);

  Future<void> loadModel(Uri host, String model, Duration keepAlive) =>
      _client(host, model: model).loadModel(model, keepAlive: keepAlive);

  Future<void> unloadModel(Uri host, String model) =>
      _client(host, model: model).unloadModel(model);

  Future<int?> showModelContext(Uri host, String model) =>
      _client(host, model: model).showModel(model);

  OllamaClient _client(Uri host, {String model = ''}) => _clientFactory(
    model: model,
    baseUrl: host,
    options: const InferenceOptions(),
  );

  static OllamaClient _defaultClientFactory({
    required String model,
    required Uri baseUrl,
    required InferenceOptions options,
  }) => OllamaClient(model: model, baseUrl: baseUrl, options: options);
}
