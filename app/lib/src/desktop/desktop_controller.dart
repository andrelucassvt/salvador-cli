import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

enum OllamaConnectionState { idle, loading, ready, failed }

enum ChatRole { user, assistant }

class ChatEntry {
  const ChatEntry({
    required this.role,
    required this.content,
    this.metrics,
    this.mentionedFiles = const [],
    this.warnings = const [],
  });

  final ChatRole role;
  final String content;
  final InferenceMetrics? metrics;
  final List<String> mentionedFiles;
  final List<String> warnings;
}

class ToolActivity {
  ToolActivity(this.call) : happenedAt = DateTime.now();

  final ToolCall call;
  final DateTime happenedAt;

  String get summary {
    final path = call.arguments['path'];
    if (path is String) return path;
    final command = call.arguments['command'];
    if (command is String) return command;
    return call.arguments.keys.join(', ');
  }
}

class DesktopController extends ChangeNotifier {
  DesktopController({Directory? initialRoot, Uri? initialHost})
    : root = (initialRoot ?? Directory.current).absolute,
      host = initialHost ?? Uri.parse('http://127.0.0.1:11434'),
      _mentions = FileMentionService(
        (initialRoot ?? Directory.current).absolute,
      );

  Uri host;
  Directory root;
  OllamaConnectionState connectionState = OllamaConnectionState.idle;
  List<String> models = const [];
  String? selectedModel;
  String? connectionError;
  bool isSending = false;

  final List<ChatEntry> messages = [];
  final List<ToolActivity> activities = [];
  FileMentionService _mentions;
  AgentSession? _session;

  Future<void> initialize() =>
      refreshConnection(hostText: host.toString(), rootPath: root.path);

  Future<void> refreshConnection({
    required String hostText,
    required String rootPath,
  }) async {
    connectionState = OllamaConnectionState.loading;
    connectionError = null;
    notifyListeners();

    try {
      final parsedHost = Uri.tryParse(hostText.trim());
      if (parsedHost == null ||
          !parsedHost.hasScheme ||
          parsedHost.host.isEmpty) {
        throw const FormatException('Informe uma URL válida para o Ollama.');
      }
      final parsedRoot = Directory(rootPath.trim()).absolute;
      if (!parsedRoot.existsSync()) {
        throw const FileSystemException('A pasta do projeto não existe.');
      }

      final discovery = OllamaDiscovery(
        host: parsedHost,
        processRunner: _runOllamaProcess,
      );
      if (!await discovery.isInstalled()) {
        throw const OllamaDiscoveryException(
          'Ollama não foi encontrado neste computador.',
        );
      }
      final discoveredModels = await discovery.listModels();
      if (discoveredModels.isEmpty) {
        throw const OllamaDiscoveryException(
          'Nenhum modelo instalado. Execute ollama pull <modelo>.',
        );
      }

      final settingsChanged =
          host != parsedHost || root.path != parsedRoot.path;
      final previousModel = selectedModel;
      host = parsedHost;
      root = parsedRoot;
      models = List.unmodifiable(discoveredModels);
      if (!models.contains(selectedModel)) selectedModel = models.first;
      _mentions = FileMentionService(root)..refresh();
      if (settingsChanged || previousModel != selectedModel) {
        clearSession(notify: false);
        _rebuildSession();
      } else if (_session == null) {
        _rebuildSession();
      }
      connectionState = OllamaConnectionState.ready;
    } on FormatException catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.message;
    } on FileSystemException catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.message;
    } on OllamaDiscoveryException catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.message;
    } catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.toString();
    }
    notifyListeners();
  }

  void selectModel(String? model) {
    if (model == null || model == selectedModel) return;
    selectedModel = model;
    clearSession(notify: false);
    _rebuildSession();
    notifyListeners();
  }

  void clearSession({bool notify = true}) {
    messages.clear();
    activities.clear();
    _session?.clear();
    if (notify) notifyListeners();
  }

  List<String> fileSuggestions(String input, int cursor, {int limit = 6}) {
    final active = _mentions.activeMention(input, cursor);
    if (active == null) return const [];
    return _mentions.suggest(active.query, limit: limit);
  }

  String insertMention(String input, int cursor, String path) {
    final active = _mentions.activeMention(input, cursor);
    if (active == null) return input;
    final encoded = path.contains(' ') ? '@"$path"' : '@$path';
    return input.replaceRange(active.start, cursor, '$encoded ');
  }

  Future<void> send(String input) async {
    final normalized = input.trim();
    if (normalized.isEmpty || isSending) return;
    if (normalized == '/clear') {
      clearSession();
      return;
    }
    if (connectionState != OllamaConnectionState.ready || _session == null) {
      connectionError = 'Conecte ao Ollama antes de enviar uma mensagem.';
      notifyListeners();
      return;
    }

    messages.add(ChatEntry(role: ChatRole.user, content: normalized));
    isSending = true;
    connectionError = null;
    notifyListeners();

    try {
      final result = await _session!.sendDetailed(normalized);
      messages.add(
        ChatEntry(
          role: ChatRole.assistant,
          content: result.answer,
          metrics: result.metrics,
          mentionedFiles: result.mentionedFiles,
          warnings: result.warnings,
        ),
      );
    } on SocketException catch (error) {
      connectionError = 'Não foi possível conectar ao Ollama: ${error.message}';
    } on OllamaException catch (error) {
      connectionError = 'Erro do Ollama: ${error.message}';
    } on AgentException catch (error) {
      connectionError = 'Erro do agente: ${error.message}';
    } catch (error) {
      connectionError = 'Falha inesperada: $error';
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  void _rebuildSession() {
    final model = selectedModel;
    if (model == null) return;
    _session = AgentSession(
      client: OllamaClient(model: model, baseUrl: host),
      root: root,
      onToolCall: (call) {
        activities.insert(0, ToolActivity(call));
        notifyListeners();
      },
    );
  }
}

Future<ProcessResult> _runOllamaProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final candidates = <String>[
    if (Platform.isMacOS) ...[
      '/opt/homebrew/bin/$executable',
      '/usr/local/bin/$executable',
    ],
    if (Platform.isLinux) ...[
      '/usr/local/bin/$executable',
      '/usr/bin/$executable',
    ],
    if (Platform.isWindows && Platform.environment['LOCALAPPDATA'] != null)
      '${Platform.environment['LOCALAPPDATA']}\\Programs\\Ollama\\$executable.exe',
    executable,
  ];

  ProcessException? lastError;
  for (final candidate in candidates) {
    if (candidate != executable && !File(candidate).existsSync()) continue;
    try {
      return await Process.run(candidate, arguments, environment: environment);
    } on ProcessException catch (error) {
      lastError = error;
    }
  }
  throw lastError ?? ProcessException(executable, arguments, 'não encontrado');
}
