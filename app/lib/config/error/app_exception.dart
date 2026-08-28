/// Hierarquia de erros deste app: conexao Ollama local + sistema de arquivos
/// confinado, sem HTTP autenticado. Nao reaproveita a hierarquia generica de
/// APIs REST (sem 401/403/statusCode) porque nada aqui exige esses casos.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType($message)';
}

/// Sem conexao, DNS, timeout - a requisicao nao chegou a ser respondida.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause, super.stackTrace});
}

/// Servidor Ollama respondeu com erro ou sem modelos instalados.
class OllamaServerException extends AppException {
  const OllamaServerException(super.message, {super.cause, super.stackTrace});
}

/// Falha do `AgentSession` durante uma rodada de tool calling.
class AgentFailureException extends AppException {
  const AgentFailureException(super.message, {super.cause, super.stackTrace});
}

/// Falha de leitura/escrita confinada ao workspace (ToolRegistry/preview).
class FileSystemFailureException extends AppException {
  const FileSystemFailureException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Entrada do usuario invalida antes de qualquer chamada externa (ex.: host
/// mal formado).
class InvalidInputException extends AppException {
  const InvalidInputException(super.message, {super.cause, super.stackTrace});
}

/// Qualquer coisa nao classificada.
class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause, super.stackTrace});
}
