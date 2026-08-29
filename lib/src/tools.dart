import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract interface class AgentTool {
  ToolDefinition get definition;

  Future<String> execute(Map<String, Object?> arguments);
}

/// Controla quais ferramentas sao expostas ao modelo e aceitas na execucao.
/// A leitura de arquivos esta sempre disponivel; edicao e comandos podem ser
/// removidos. [readOnly] cobre os consumidores que so podem ler.
class AgentPermissions {
  const AgentPermissions({this.allowEdit = true, this.allowCommands = true});

  static const readOnly = AgentPermissions(
    allowEdit: false,
    allowCommands: false,
  );

  final bool allowEdit;
  final bool allowCommands;

  bool allows(String toolName) => switch (toolName) {
    'write_file' || 'replace_in_file' => allowEdit,
    'run_command' => allowCommands,
    _ => true,
  };
}

class ToolRegistry {
  ToolRegistry(
    Directory? root, {
    AgentPermissions permissions = const AgentPermissions(),
  }) : _permissions = permissions,
       _tools = root == null
           ? const []
           : [
               ReadFileTool(root),
               if (permissions.allowEdit) WriteFileTool(root),
               if (permissions.allowEdit) ReplaceInFileTool(root),
               if (permissions.allowCommands) RunCommandTool(root),
             ];

  final AgentPermissions _permissions;
  final List<AgentTool> _tools;

  List<ToolDefinition> get definitions =>
      _tools.map((tool) => tool.definition).toList(growable: false);

  Future<String> execute(ToolCall call) async {
    final tool = _tools.where(
      (candidate) => candidate.definition.name == call.name,
    );
    if (tool.isEmpty) {
      if (!_permissions.allows(call.name)) {
        return 'ERRO: ferramenta nao permitida: ${call.name}';
      }
      return 'ERRO: ferramenta desconhecida: ${call.name}';
    }

    try {
      return await tool.single.execute(call.arguments);
    } on ToolException catch (error) {
      return 'ERRO: ${error.message}';
    } on FileSystemException catch (error) {
      return 'ERRO: ${error.message}';
    } on ProcessException catch (error) {
      return 'ERRO: ${error.message}';
    } on TimeoutException {
      return 'ERRO: comando excedeu o limite de tempo';
    }
  }
}

abstract class WorkspaceTool implements AgentTool {
  WorkspaceTool(Directory root)
    : root = Directory(root.resolveSymbolicLinksSync());

  final Directory root;

  String requiredString(Map<String, Object?> arguments, String name) {
    final value = arguments[name];
    if (value is! String || value.isEmpty) {
      throw ToolException('argumento "$name" deve ser uma string nao vazia');
    }
    return value;
  }

  File resolveFile(String path, {required bool mayCreate}) {
    final candidateUri = root.uri.resolveUri(Uri(path: path));
    if (candidateUri.scheme != 'file') {
      throw const ToolException('caminho invalido');
    }
    final candidate = File.fromUri(candidateUri);
    _ensureInside(candidate.path);

    if (candidate.existsSync()) {
      _ensureInside(candidate.resolveSymbolicLinksSync());
      return candidate;
    }

    if (!mayCreate) throw ToolException('arquivo nao encontrado: $path');
    var parent = candidate.parent;
    while (!parent.existsSync()) {
      final next = parent.parent;
      if (next.path == parent.path) {
        throw const ToolException('nao foi possivel validar o caminho');
      }
      parent = next;
    }
    _ensureInside(parent.resolveSymbolicLinksSync());
    return candidate;
  }

  void _ensureInside(String path) {
    final rootPath = root.path;
    if (path != rootPath &&
        !path.startsWith('$rootPath${Platform.pathSeparator}')) {
      throw const ToolException('acesso fora da raiz nao permitido');
    }
  }
}

class ReadFileTool extends WorkspaceTool {
  ReadFileTool(super.root);

  static const _maxCharacters = 100000;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'read_file',
    description: 'Le um arquivo de texto dentro da raiz do projeto.',
    properties: {
      'path': {'type': 'string', 'description': 'Caminho relativo do arquivo'},
    },
    required: ['path'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final path = requiredString(arguments, 'path');
    final file = resolveFile(path, mayCreate: false);
    final bytes = await file.readAsBytes();
    if (bytes.contains(0)) {
      throw const ToolException('arquivo binario nao pode ser lido');
    }
    final String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      throw const ToolException('arquivo nao esta em UTF-8');
    }
    if (content.length <= _maxCharacters) return content;
    return '${content.substring(0, _maxCharacters)}\n[TRUNCADO]';
  }
}

class WriteFileTool extends WorkspaceTool {
  WriteFileTool(super.root);

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'write_file',
    description: 'Cria ou sobrescreve um arquivo de texto dentro da raiz.',
    properties: {
      'path': {'type': 'string', 'description': 'Caminho relativo do arquivo'},
      'content': {
        'type': 'string',
        'description': 'Conteudo completo do arquivo',
      },
    },
    required: ['path', 'content'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final path = requiredString(arguments, 'path');
    final content = arguments['content'];
    if (content is! String) {
      throw const ToolException('argumento "content" deve ser uma string');
    }
    final file = resolveFile(path, mayCreate: true);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    return 'OK: arquivo gravado: $path (${content.length} caracteres)';
  }
}

class ReplaceInFileTool extends WorkspaceTool {
  ReplaceInFileTool(super.root);

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'replace_in_file',
    description: 'Substitui uma ocorrencia exata em um arquivo de texto.',
    properties: {
      'path': {'type': 'string', 'description': 'Caminho relativo do arquivo'},
      'old_text': {'type': 'string', 'description': 'Texto exato existente'},
      'new_text': {'type': 'string', 'description': 'Novo texto'},
    },
    required: ['path', 'old_text', 'new_text'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final path = requiredString(arguments, 'path');
    final oldText = requiredString(arguments, 'old_text');
    final newText = arguments['new_text'];
    if (newText is! String) {
      throw const ToolException('argumento "new_text" deve ser uma string');
    }

    final file = resolveFile(path, mayCreate: false);
    final content = await file.readAsString();
    final first = content.indexOf(oldText);
    if (first < 0) throw const ToolException('old_text nao encontrado');
    if (content.indexOf(oldText, first + oldText.length) >= 0) {
      throw const ToolException(
        'old_text aparece mais de uma vez; envie mais contexto',
      );
    }

    final updated = content.replaceRange(
      first,
      first + oldText.length,
      newText,
    );
    await file.writeAsString(updated);
    return 'OK: arquivo editado: $path';
  }
}

class RunCommandTool extends WorkspaceTool {
  RunCommandTool(super.root);

  static const _maxOutput = 20000;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_command',
    description:
        'Executa um comando na raiz do projeto e retorna saida e codigo.',
    properties: {
      'command': {'type': 'string', 'description': 'Comando shell a executar'},
    },
    required: ['command'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final command = requiredString(arguments, 'command');
    final executable = Platform.isWindows ? 'cmd.exe' : '/bin/sh';
    final shellArguments = Platform.isWindows
        ? ['/c', command]
        : ['-lc', command];
    final process = await Process.start(
      executable,
      shellArguments,
      workingDirectory: root.path,
      runInShell: false,
    );

    try {
      final results = await Future.wait<Object>([
        utf8.decoder.bind(process.stdout).join(),
        utf8.decoder.bind(process.stderr).join(),
        process.exitCode,
      ]).timeout(const Duration(seconds: 30));
      final stdoutText = results[0] as String;
      final stderrText = results[1] as String;
      final exitCode = results[2] as int;
      final output = [
        if (stdoutText.isNotEmpty) stdoutText,
        if (stderrText.isNotEmpty) 'STDERR:\n$stderrText',
        'EXIT_CODE: $exitCode',
      ].join('\n');
      if (output.length <= _maxOutput) return output;
      return '${output.substring(0, _maxOutput)}\n[TRUNCADO]';
    } on TimeoutException {
      process.kill();
      rethrow;
    }
  }
}

class ToolException implements Exception {
  const ToolException(this.message);

  final String message;
}
