import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';

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

  final lines = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  final model = config.model ?? await _selectModel(models, lines);
  if (model == null) {
    stdout.writeln('\nAte logo.');
    return;
  }
  if (!models.contains(model)) {
    stderr.writeln('O modelo "$model" nao aparece em `ollama list`.');
    exitCode = 64;
    return;
  }

  final session = AgentSession(
    client: OllamaClient(model: model, baseUrl: config.host),
    root: config.root,
    onToolCall: (call) => stdout.writeln('  > ${call.name}'),
  );

  stdout.writeln('\nLeve CLI | $model | ${config.root.path}');
  stdout.writeln('Digite /exit para sair.');
  stdout.write('\nvoce> ');

  while (await lines.moveNext()) {
    final input = lines.current.trim();
    if (input == '/exit' || input == '/quit') break;
    if (input == '/clear') {
      session.clear();
      stdout.writeln('Sessao limpa.');
      stdout.write('\nvoce> ');
      continue;
    }
    if (input.isEmpty) {
      stdout.write('voce> ');
      continue;
    }

    try {
      final answer = await session.send(input);
      stdout.writeln('\nleve> $answer');
    } on SocketException catch (error) {
      stderr.writeln('\nNao foi possivel conectar ao Ollama: ${error.message}');
    } on OllamaException catch (error) {
      stderr.writeln('\nErro do Ollama: $error');
    } on AgentException catch (error) {
      stderr.writeln('\nErro do agente: $error');
    }
    stdout.write('\nvoce> ');
  }

  stdout.writeln('\nAte logo.');
}

Future<String?> _selectModel(
  List<String> models,
  StreamIterator<String> lines,
) async {
  while (true) {
    stdout.write('Selecione o modelo [1-${models.length}] ou /exit: ');
    if (!await lines.moveNext()) return null;
    final input = lines.current.trim();
    if (input == '/exit' || input == '/quit') return null;

    final selection = int.tryParse(input);
    if (selection != null && selection >= 1 && selection <= models.length) {
      return models[selection - 1];
    }
    stdout.writeln('Selecao invalida. Digite o numero de um modelo.');
  }
}
