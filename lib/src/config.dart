import 'dart:io';

class CliConfig {
  const CliConfig({
    required this.model,
    required this.host,
    required this.root,
  });

  factory CliConfig.parse(List<String> arguments) {
    var model = Platform.environment['OLLAMA_MODEL'];
    var host = Platform.environment['OLLAMA_HOST'] ?? 'http://127.0.0.1:11434';
    var root = Directory.current.path;

    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      String nextValue() {
        if (index + 1 >= arguments.length) {
          throw FormatException('Falta valor para $argument.');
        }
        return arguments[++index];
      }

      switch (argument) {
        case '--model':
          model = nextValue();
        case '--host':
          host = nextValue();
        case '--root':
          root = nextValue();
        case '--help' || '-h':
          throw const HelpRequested();
        default:
          throw FormatException('Opcao desconhecida: $argument');
      }
    }

    final hostUri = Uri.tryParse(host);
    if (hostUri == null || !hostUri.hasScheme || hostUri.host.isEmpty) {
      throw FormatException('Host invalido: $host');
    }

    final rootDirectory = Directory(root).absolute;
    if (!rootDirectory.existsSync()) {
      throw FormatException('Raiz nao encontrada: ${rootDirectory.path}');
    }

    return CliConfig(model: model, host: hostUri, root: rootDirectory);
  }

  final String? model;
  final Uri host;
  final Directory root;
}

class HelpRequested implements Exception {
  const HelpRequested();
}

const cliUsage = '''Leve CLI - agente de codigo para Ollama

Uso: dart run bin/salvador_cli.dart [opcoes]

  --model NOME   Escolhe o modelo sem perguntar (padrao: selecao interativa)
  --host URL     URL do Ollama (padrao: http://127.0.0.1:11434)
  --root CAMINHO Raiz permitida para as ferramentas (padrao: diretorio atual)
  -h, --help     Exibe esta ajuda

No chat, use /clear para limpar a sessao e /exit para sair.''';
