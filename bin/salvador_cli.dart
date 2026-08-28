import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';

const _exitCommands = [
  TerminalCommand('/exit', 'Encerra o programa'),
  TerminalCommand('/quit', 'Encerra o programa'),
];

const _chatCommands = [
  TerminalCommand('/clear', 'Limpa o historico da sessao'),
  ..._exitCommands,
];

Future<void> main(List<String> arguments) async {
  late final CliConfig config;
  try {
    config = CliConfig.parse(arguments);
  } on HelpRequested {
    stdout.writeln(cliUsage);
    return;
  } on FormatException catch (error) {
    stderr.writeln('Erro: ${error.message}\n');
    stderr.writeln(cliUsage);
    exitCode = 64;
    return;
  }

  final discovery = OllamaDiscovery(host: config.host);
  if (!await discovery.isInstalled()) {
    stderr.writeln(
      'Ollama nao encontrado. Instale o Ollama e tente novamente: '
      'https://ollama.com/download',
    );
    exitCode = 69;
    return;
  }

  late final List<String> models;
  try {
    models = await discovery.listModels();
  } on OllamaDiscoveryException catch (error) {
    stderr.writeln('Nao foi possivel listar os modelos do Ollama: $error');
    stderr.writeln('Confirme que o servico Ollama esta em execucao.');
    exitCode = 69;
    return;
  }

  if (models.isEmpty) {
    stderr.writeln('Nenhum modelo instalado no Ollama.');
    stderr.writeln(
      'Instale um modelo, por exemplo: ollama pull qwen2.5-coder:3b',
    );
    exitCode = 69;
    return;
  }

  stdout.writeln('Modelos disponiveis:');
  for (var index = 0; index < models.length; index++) {
    stdout.writeln('  ${index + 1}) ${models[index]}');
  }

  final terminal = TerminalInput();
  try {
    final model = config.model ?? await _selectModel(models, terminal);
    if (model == null) {
      stdout.writeln('\nAte logo.');
      return;
    }
    if (!models.contains(model)) {
      stderr.writeln('O modelo "$model" nao aparece em `ollama list`.');
      exitCode = 64;
      return;
    }

    await _chat(config, model, terminal);
  } on TerminalInputInterrupted {
    stdout.writeln('\nAte logo.');
  } finally {
    await terminal.close();
  }
}

Future<String?> _selectModel(
  List<String> models,
  TerminalInput terminal,
) async {
  while (true) {
    final line = await terminal.readLine(
      prompt: 'Selecione o modelo [1-${models.length}] ou /exit: ',
      commands: _exitCommands,
    );
    if (line == null) return null;
    final input = line.trim();
    if (input == '/exit' || input == '/quit') return null;

    final selection = int.tryParse(input);
    if (selection != null && selection >= 1 && selection <= models.length) {
      return models[selection - 1];
    }
    stdout.writeln('Selecao invalida. Digite o numero de um modelo.');
  }
}

Future<void> _chat(
  CliConfig config,
  String model,
  TerminalInput terminal,
) async {
  final session = AgentSession(
    client: OllamaClient(model: model, baseUrl: config.host),
    root: config.root,
    onToolCall: (call) => stdout.writeln('  > ${call.name}'),
  );
  final mentions = FileMentionService(config.root);

  stdout.writeln('\nLeve CLI | $model | ${config.root.path}');
  stdout.writeln('Digite @ para mencionar arquivos (setas + Tab).');
  stdout.writeln('Digite / para ver os comandos (setas + Tab).');

  while (true) {
    stdout.writeln();
    final line = await terminal.readLine(
      prompt: 'voce> ',
      mentions: mentions,
      commands: _chatCommands,
    );
    if (line == null) break;
    final input = line.trim();
    if (input == '/exit' || input == '/quit') break;
    if (input == '/clear') {
      session.clear();
      stdout.writeln('Sessao limpa.');
      continue;
    }
    if (input.isEmpty) continue;

    try {
      final result = await session.sendDetailed(input);
      for (final warning in result.warnings) {
        stderr.writeln('  aviso> $warning');
      }
      stdout.writeln('\nleve> ${result.answer}');
      final metrics = result.metrics;
      if (metrics != null) stdout.writeln(formatInferenceMetrics(metrics));
    } on SocketException catch (error) {
      stderr.writeln('\nNao foi possivel conectar ao Ollama: ${error.message}');
    } on OllamaException catch (error) {
      stderr.writeln('\nErro do Ollama: $error');
    } on AgentException catch (error) {
      stderr.writeln('\nErro do agente: $error');
    }
  }

  stdout.writeln('\nAte logo.');
}
