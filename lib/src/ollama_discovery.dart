import 'dart:io';

typedef OllamaProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class OllamaDiscovery {
  OllamaDiscovery({this.host, OllamaProcessRunner? processRunner})
    : _processRunner = processRunner ?? _runProcess;

  final Uri? host;
  final OllamaProcessRunner _processRunner;

  Future<bool> isInstalled() async {
    try {
      await _processRunner('ollama', const [
        '--help',
      ], environment: _environment);
      return true;
    } on ProcessException {
      return false;
    }
  }

  Future<List<String>> listModels() async {
    late final ProcessResult result;
    try {
      result = await _processRunner('ollama', const [
        'list',
      ], environment: _environment);
    } on ProcessException catch (error) {
      throw OllamaDiscoveryException(error.message);
    }

    if (result.exitCode != 0) {
      final details = (result.stderr as String).trim();
      throw OllamaDiscoveryException(
        details.isEmpty
            ? 'ollama list terminou com codigo ${result.exitCode}'
            : details,
      );
    }

    return parseModelList(result.stdout as String);
  }

  Map<String, String>? get _environment =>
      host == null ? null : {'OLLAMA_HOST': host.toString()};

  static List<String> parseModelList(String output) {
    final models = <String>[];
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.toUpperCase().startsWith('NAME ')) {
        continue;
      }
      final name = trimmed.split(RegExp(r'\s+')).first;
      if (!models.contains(name)) models.add(name);
    }
    return models;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) => Process.run(executable, arguments, environment: environment);
}

class OllamaDiscoveryException implements Exception {
  const OllamaDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}
