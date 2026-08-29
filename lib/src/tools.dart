import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'context_files.dart';
import 'git.dart';
import 'models.dart';

abstract interface class AgentTool {
  ToolDefinition get definition;

  Future<String> execute(Map<String, Object?> arguments);
}

typedef GitActionConfirmation =
    FutureOr<bool> Function(GitActionProposal proposal);

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

/// Perfil Git opcional de uma sessao: consultas estruturadas e a ferramenta
/// tipada `git`. Por padrao substitui `run_command`, mas o chat principal e a
/// CLI podem manter o shell com [replacesRunCommand] falso.
class GitProfile {
  const GitProfile({
    this.queriesEnabled = true,
    this.proposalsEnabled = true,
    this.replacesRunCommand = true,
  });

  final bool queriesEnabled;
  final bool proposalsEnabled;
  final bool replacesRunCommand;
}

class ToolRegistry {
  ToolRegistry(
    Directory? root, {
    AgentPermissions permissions = const AgentPermissions(),
    ContextFilesService? contextFiles,
    GitClient? gitClient,
    GitProfile? gitProfile,
    void Function(GitActionProposal)? onProposal,
    GitActionConfirmation? onGitConfirm,
    GitActionExecutor? gitActionExecutor,
  }) : _permissions = permissions,
       _tools = root == null
           ? const []
           : [
               ReadFileTool(root),
               if (contextFiles != null) UseSkillTool(root, contextFiles),
               if (permissions.allowEdit) WriteFileTool(root),
               if (permissions.allowEdit) ReplaceInFileTool(root),
               if (permissions.allowCommands &&
                   (gitProfile == null || !gitProfile.replacesRunCommand))
                 RunCommandTool(root),
               if (gitClient != null && gitProfile != null) ...[
                 if (gitProfile.queriesEnabled) ...[
                   GitStatusTool(root, gitClient),
                   GitLogTool(root, gitClient),
                   GitDiffTool(root, gitClient),
                   GitShowTool(root, gitClient),
                 ],
                 if (gitProfile.proposalsEnabled)
                   GitActionTool(
                     root,
                     onProposal: onProposal,
                     onGitConfirm: onGitConfirm,
                     executor: gitActionExecutor,
                   ),
               ],
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
    } on GitException catch (error) {
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

class UseSkillTool extends WorkspaceTool {
  UseSkillTool(super.root, this._contextFiles);

  final ContextFilesService _contextFiles;

  @override
  ToolDefinition get definition {
    final skills = _contextFiles.discoverSkills();
    final available = skills.isEmpty
        ? 'nenhuma'
        : skills
              .map(
                (skill) => skill.description.isEmpty
                    ? skill.name
                    : '${skill.name} (${skill.description})',
              )
              .join(', ');
    return ToolDefinition(
      name: 'use_skill',
      description: 'Le as instrucoes de uma skill. Disponiveis: $available.',
      properties: const {
        'name': {'type': 'string', 'description': 'Nome da skill'},
      },
      required: const ['name'],
    );
  }

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final name = requiredString(arguments, 'name');
    final content = _contextFiles.skillContent(name);
    if (content != null) return content;
    final available = _contextFiles
        .discoverSkills()
        .map((skill) => skill.name)
        .join(', ');
    throw ToolException(
      'skill nao encontrada: $name. Skills disponiveis: '
      '${available.isEmpty ? "nenhuma" : available}',
    );
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

/// Base das consultas Git: compartilha o [GitClient] e o limite de saida.
abstract class GitQueryTool extends WorkspaceTool {
  GitQueryTool(super.root, this.client);

  static const maxOutput = 6000;

  final GitClient client;

  void _validatePath(String path) {
    if (path.isEmpty ||
        path.startsWith('-') ||
        path.startsWith('/') ||
        path.split('/').contains('..')) {
      throw const ToolException('caminho invalido');
    }
    final candidateUri = root.uri.resolveUri(Uri(path: path));
    if (candidateUri.scheme != 'file') {
      throw const ToolException('caminho invalido');
    }
    _ensureInside(candidateUri.toFilePath());
  }

  String truncate(String output) => output.length <= maxOutput
      ? output
      : '${output.substring(0, maxOutput)}\n[TRUNCADO]';
}

/// Resumo estruturado do repositorio para o assistente Git.
class GitStatusTool extends GitQueryTool {
  GitStatusTool(super.root, super.client);

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'git_status',
    description:
        'Resumo estruturado do repositorio: branch, estado '
        'sujo/limpo, ahead/behind, upstream, refs, stashes e alteracoes '
        'locais.',
    properties: {},
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final snapshot = await client.loadSnapshot(root);
    if (!snapshot.repository.isValid) {
      return 'ERRO: repositorio invalido para esta raiz';
    }
    return truncate(serializeGitContext(snapshot, maxCommits: 0));
  }
}

/// Ultimos commits do repositorio.
class GitLogTool extends GitQueryTool {
  GitLogTool(super.root, super.client);

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'git_log',
    description: 'Lista os commits mais recentes com hash curto e assunto.',
    properties: {
      'count': {
        'type': 'integer',
        'description': 'Quantidade de commits (maximo 30, padrao 10)',
      },
    },
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final rawCount = arguments['count'];
    final count = rawCount is num ? rawCount.toInt().clamp(1, 30) : 10;
    final snapshot = await client.loadSnapshot(root, maxCommits: count);
    if (!snapshot.repository.isValid) {
      return 'ERRO: repositorio invalido para esta raiz';
    }
    final buffer = StringBuffer()
      ..writeln('Commits (${snapshot.commits.length}):');
    for (final commit in snapshot.commits) {
      buffer.writeln(
        '- ${commit.shortHash} ${commit.subject}'
        '${commit.isMerge ? ' [merge]' : ''}',
      );
    }
    if (snapshot.commitsTruncated) buffer.writeln('[TRUNCADO]');
    return buffer.toString();
  }
}

/// Diff atual de um arquivo do worktree.
class GitDiffTool extends GitQueryTool {
  GitDiffTool(super.root, super.client);

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'git_diff',
    description:
        'Mostra o diff de um arquivo do worktree contra o HEAD '
        '(ate 6000 caracteres).',
    properties: {
      'path': {'type': 'string', 'description': 'Caminho relativo'},
    },
    required: ['path'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final path = requiredString(arguments, 'path');
    _validatePath(path);
    final output = await client.runReadOnly(root, ['diff', 'HEAD', '--', path]);
    return truncate(output);
  }
}

/// Detalhes e estatisticas de um commit.
class GitShowTool extends GitQueryTool {
  GitShowTool(super.root, super.client);

  static final RegExp _commitRef = RegExp(r'^(HEAD|[0-9a-fA-F]{7,40})$');

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'git_show',
    description:
        'Mostra o assunto, autor e estatisticas de um commit '
        '(ate 6000 caracteres).',
    properties: {
      'commit': {
        'type': 'string',
        'description': 'Hash curto/completo ou HEAD',
      },
    },
    required: ['commit'],
  );

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final commit = requiredString(arguments, 'commit').trim();
    if (!_commitRef.hasMatch(commit)) {
      throw ToolException('commit invalido: $commit');
    }
    final output = await client.runReadOnly(root, [
      'show',
      '--stat',
      '--format=commit %H%nAutor: %an <%ae>%nData: %aI%n%n%s%n%n%b',
      commit,
    ]);
    return truncate(output);
  }
}

/// Executa operacoes Git normais e somente registra as riscosas para revisao
/// quando nao ha um callback de confirmacao no frontend.
class GitActionTool extends WorkspaceTool {
  GitActionTool(
    super.root, {
    this.onProposal,
    this.onGitConfirm,
    GitActionExecutor? executor,
  }) : _executor = executor ?? GitActionExecutor();

  final void Function(GitActionProposal)? onProposal;
  final GitActionConfirmation? onGitConfirm;
  final GitActionExecutor _executor;

  @override
  ToolDefinition get definition {
    final types = GitActionType.values.map((type) => type.name).join(', ');
    return ToolDefinition(
      name: 'git',
      description:
          'Executa uma operacao Git tipada. Tipos validos: $types. '
          'Operacoes riscosas exigem confirmacao.',
      properties: const {
        'type': {'type': 'string', 'description': 'Tipo da operacao Git'},
        'ref': {'type': 'string', 'description': 'Ref, branch, tag ou remoto'},
        'paths': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'Caminhos relativos para arquivos',
        },
        'message': {
          'type': 'string',
          'description': 'Mensagem de commit, stash ou URL do remoto',
        },
      },
      required: const ['type'],
    );
  }

  @override
  Future<String> execute(Map<String, Object?> arguments) async {
    final typeName = requiredString(arguments, 'type');
    final type = _typeFor(typeName);
    final rawRef = arguments['ref'];
    if (rawRef != null && rawRef is! String) {
      throw const ToolException('argumento "ref" deve ser uma string');
    }
    final rawMessage = arguments['message'];
    if (rawMessage != null && rawMessage is! String) {
      throw const ToolException('argumento "message" deve ser uma string');
    }
    final paths = _pathsFor(arguments['paths']);
    final proposal = GitActionProposal(
      type: type,
      refName: rawRef as String?,
      paths: paths,
      message: rawMessage as String?,
    );

    // Valida antes de confirmar ou propor para a LLM poder corrigir os args.
    _executor.validate(proposal, root);
    if (proposal.risk == GitActionRisk.normal) {
      return _executor.execute(proposal, root);
    }
    if (onGitConfirm != null) {
      if (await onGitConfirm!(proposal)) {
        return _executor.execute(proposal, root);
      }
      throw const ToolException('operacao cancelada pelo usuario');
    }
    if (onProposal != null) {
      onProposal!(proposal);
      return 'Proposta registrada: ${proposal.summary}. '
          'Aguardando aprovacao na interface.';
    }
    throw const ToolException('operacao destrutiva requer aprovacao');
  }

  GitActionType _typeFor(String name) {
    for (final type in GitActionType.values) {
      if (type.name == name) return type;
    }
    throw ToolException('tipo de acao invalido: $name');
  }

  List<String> _pathsFor(Object? rawPaths) {
    if (rawPaths == null) return const [];
    if (rawPaths is! List) {
      throw const ToolException('argumento "paths" deve ser uma lista');
    }
    final paths = <String>[];
    for (final path in rawPaths) {
      if (path is! String) {
        throw const ToolException('caminho invalido em "paths"');
      }
      paths.add(path);
    }
    return paths;
  }
}
