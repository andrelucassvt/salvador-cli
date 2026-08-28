import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

import 'desktop_state_store.dart';
import 'system_memory.dart';

enum OllamaConnectionState { idle, loading, ready, failed }

enum ModelRunState { stopped, starting, running }

enum ChatRole { user, assistant }

typedef OllamaClientFactory =
    OllamaClient Function({
      required String model,
      required Uri baseUrl,
      required InferenceOptions options,
    });

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
  ToolActivity(this.call, this.result, {DateTime? happenedAt})
    : happenedAt = happenedAt ?? DateTime.now();

  final ToolCall call;
  final String result;
  final DateTime happenedAt;

  String get summary {
    final path = call.arguments['path'];
    if (path is String) return path;
    final command = call.arguments['command'];
    if (command is String) return command;
    return call.arguments.keys.join(', ');
  }
}

class HostTestResult {
  const HostTestResult({
    required this.ok,
    this.latency,
    this.modelCount = 0,
    this.error,
  });

  final bool ok;
  final Duration? latency;
  final int modelCount;
  final String? error;
}

class DesktopController extends ChangeNotifier {
  DesktopController({
    Directory? initialRoot,
    Uri? initialHost,
    DesktopStateStore? store,
    OllamaClientFactory? clientFactory,
    SystemMemoryReader? memoryReader,
    DateTime Function()? clock,
  }) : root = (initialRoot ?? Directory.current).absolute,
       host = initialHost ?? Uri.parse('http://127.0.0.1:11434'),
       _store = store ?? DesktopStateStore(),
       _clientFactory = clientFactory ?? _defaultClientFactory,
       _memoryReader = memoryReader ?? SystemMemoryReader(),
       _clock = clock ?? DateTime.now,
       _mentions = FileMentionService(
         (initialRoot ?? Directory.current).absolute,
       );

  static const _defaultKeepAlive = Duration(minutes: 5);
  static const _maxSessionTitleLength = 80;

  Uri host;
  Directory root;
  OllamaConnectionState connectionState = OllamaConnectionState.idle;
  ModelRunState modelState = ModelRunState.stopped;
  List<OllamaModelInfo> models = const [];
  List<OllamaRunningModel> runningModels = const [];
  String? selectedModel;
  String? connectionError;
  bool isSending = false;

  double temperature = 0.1;
  int? contextLength;
  Duration? keepAlive;
  Duration? timeout;
  bool allowEdit = true;
  bool allowCommands = true;

  List<String> recentRoots = const [];
  List<PersistedSessionSummary> sessions = const [];
  HostTestResult? lastTestResult;

  final List<ChatEntry> messages = [];
  final List<ToolActivity> activities = [];

  final DesktopStateStore _store;
  final OllamaClientFactory _clientFactory;
  final SystemMemoryReader _memoryReader;
  final DateTime Function() _clock;
  FileMentionService _mentions;
  OllamaClient? _client;
  AgentSession? _session;
  String? _sessionFirstPrompt;
  DateTime? _sessionStartedAt;

  InferenceOptions get inference => InferenceOptions(
    temperature: temperature,
    contextLength: contextLength,
    keepAlive: keepAlive,
    timeout: timeout,
  );

  AgentPermissions get permissions =>
      AgentPermissions(allowEdit: allowEdit, allowCommands: allowCommands);

  Future<void> initialize() async {
    final saved = await _store.load();
    host = saved.host ?? host;
    selectedModel = saved.model;
    temperature = saved.inference.temperature;
    contextLength = saved.inference.contextLength;
    keepAlive = saved.inference.keepAlive;
    timeout = saved.inference.timeout;
    allowEdit = saved.permissions.allowEdit;
    allowCommands = saved.permissions.allowCommands;
    recentRoots = List.of(saved.recentRoots);
    sessions = List.of(saved.sessions);

    final savedRoot = saved.activeRoot;
    if (savedRoot != null && Directory(savedRoot).existsSync()) {
      root = Directory(savedRoot).absolute;
    }
    _mentions = FileMentionService(root)..refresh();

    try {
      await _performConnect();
    } catch (_) {}
    await _persist();
    notifyListeners();
  }

  /// Caminho de compatibilidade do shell anterior: valida servidor e pasta e
  /// reconecta. Mantido enquanto a UI antiga estiver em uso.
  Future<void> refreshConnection({
    required String hostText,
    required String rootPath,
  }) async {
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

      final changed = host != parsedHost || root.path != parsedRoot.path;
      host = parsedHost;
      root = parsedRoot;
      _mentions = FileMentionService(root)..refresh();
      recentRoots = [
        root.path,
        ...recentRoots.where((candidate) => candidate != root.path),
      ];
      try {
        await _performConnect(clearHistory: changed);
      } catch (_) {}
      await _persist();
    } on FormatException catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.message;
    } on FileSystemException catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = error.message;
    }
    notifyListeners();
  }

  Future<void> selectRoot(String path) async {
    final candidate = Directory(path).absolute;
    if (!candidate.existsSync()) {
      connectionError = 'A pasta nao existe: ${candidate.path}';
      notifyListeners();
      return;
    }
    root = candidate;
    _mentions = FileMentionService(root)..refresh();
    recentRoots = [
      root.path,
      ...recentRoots.where((recent) => recent != root.path),
    ];
    clearSession(notify: false);
    await _persist();
    _rebuildSession();
    notifyListeners();
  }

  Future<void> selectModel(String? model) async {
    if (model == null || model == selectedModel) return;
    final client = _client;
    if (client == null) {
      selectedModel = model;
      notifyListeners();
      return;
    }

    modelState = ModelRunState.starting;
    connectionError = null;
    notifyListeners();
    try {
      _client = _clientFactory(model: model, baseUrl: host, options: inference);
      await _client!.loadModel(
        model,
        keepAlive: keepAlive ?? _defaultKeepAlive,
      );
      selectedModel = model;
      await _persist();
      clearSession(notify: false);
      _rebuildSession();
      await _refreshRunningModels();
      _updateModelState();
    } catch (error) {
      modelState = ModelRunState.stopped;
      connectionError = _errorText(error);
    }
    notifyListeners();
  }

  Future<void> startModel() async {
    final model = selectedModel;
    if (model == null || modelState != ModelRunState.stopped) return;
    modelState = ModelRunState.starting;
    connectionError = null;
    notifyListeners();
    try {
      await _client!.loadModel(
        model,
        keepAlive: keepAlive ?? _defaultKeepAlive,
      );
      await _refreshRunningModels();
      _updateModelState();
    } catch (error) {
      modelState = ModelRunState.stopped;
      connectionError = _errorText(error);
    }
    notifyListeners();
  }

  Future<void> stopModel() async {
    final model = selectedModel;
    if (model == null || modelState != ModelRunState.running) return;
    modelState = ModelRunState.starting;
    connectionError = null;
    notifyListeners();
    try {
      await _client!.unloadModel(model);
      await _refreshRunningModels();
      _updateModelState();
    } catch (error) {
      _updateModelState();
      connectionError = _errorText(error);
    }
    notifyListeners();
  }

  Future<HostTestResult> testHost(String hostText) async {
    final parsed = Uri.tryParse(hostText.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      lastTestResult = const HostTestResult(
        ok: false,
        error: 'Informe uma URL válida para o Ollama.',
      );
      notifyListeners();
      return lastTestResult!;
    }

    final probe = _clientFactory(
      model: selectedModel ?? '',
      baseUrl: parsed,
      options: inference,
    );
    final stopwatch = Stopwatch()..start();
    try {
      await probe.testConnection();
      final count = (await probe.listModels()).length;
      stopwatch.stop();
      lastTestResult = HostTestResult(
        ok: true,
        latency: stopwatch.elapsed,
        modelCount: count,
      );
    } catch (error) {
      stopwatch.stop();
      lastTestResult = HostTestResult(
        ok: false,
        latency: stopwatch.elapsed,
        error: _errorText(error),
      );
    }
    notifyListeners();
    return lastTestResult!;
  }

  Future<void> saveSettings({
    required String hostText,
    required double temperature,
    required int? contextLength,
    required Duration? keepAlive,
    required Duration? timeout,
    required bool allowEdit,
    required bool allowCommands,
  }) async {
    final parsed = Uri.tryParse(hostText.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw const FormatException('Informe uma URL válida para o Ollama.');
    }

    final nextInference = InferenceOptions(
      temperature: temperature,
      contextLength: contextLength,
      keepAlive: keepAlive,
      timeout: timeout,
    );
    final hostChanged = parsed != host;
    if (hostChanged) {
      final probe = _clientFactory(
        model: selectedModel ?? '',
        baseUrl: parsed,
        options: nextInference,
      );
      final nextModels = await probe.listModels();
      if (nextModels.isEmpty) {
        throw const OllamaException(
          'Nenhum modelo instalado. Execute ollama pull <modelo>.',
        );
      }
      final nextRunning = await probe.listRunningModels(installed: nextModels);
      host = parsed;
      models = List.unmodifiable(nextModels);
      runningModels = List.unmodifiable(nextRunning);
      final currentModel = selectedModel;
      if (currentModel == null ||
          !nextModels.any((model) => model.name == currentModel)) {
        selectedModel = nextModels.first.name;
      }
      _client = _clientFactory(
        model: selectedModel!,
        baseUrl: parsed,
        options: nextInference,
      );
      _updateModelState();
      clearSession(notify: false);
    } else if (selectedModel != null) {
      _client = _clientFactory(
        model: selectedModel!,
        baseUrl: host,
        options: nextInference,
      );
    }

    this.temperature = temperature;
    this.contextLength = contextLength;
    this.keepAlive = keepAlive;
    this.timeout = timeout;
    this.allowEdit = allowEdit;
    this.allowCommands = allowCommands;

    await _persist();
    _rebuildSession();
    notifyListeners();
  }

  Future<void> newSession() async {
    final firstPrompt = _sessionFirstPrompt;
    if (firstPrompt != null) {
      final title = firstPrompt.length > _maxSessionTitleLength
          ? firstPrompt.substring(0, _maxSessionTitleLength)
          : firstPrompt;
      sessions = [
        PersistedSessionSummary(
          title: title,
          startedAt: _sessionStartedAt ?? _clock(),
          actionCount: activities.length,
        ),
        ...sessions,
      ];
      await _persist();
    }
    clearSession();
  }

  void clearSession({bool notify = true}) {
    messages.clear();
    activities.clear();
    _sessionFirstPrompt = null;
    _sessionStartedAt = null;
    _session?.clear();
    if (notify) notifyListeners();
  }

  Future<int?> availableMemory() => _memoryReader.availableBytes();

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
    if (modelState != ModelRunState.running) {
      connectionError =
          'O modelo selecionado esta parado. Inicie o modelo antes de enviar.';
      notifyListeners();
      return;
    }

    _sessionFirstPrompt ??= normalized;
    _sessionStartedAt ??= _clock();
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
    } catch (error) {
      connectionError = _errorText(error);
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<void> _performConnect({bool clearHistory = false}) async {
    connectionState = OllamaConnectionState.loading;
    connectionError = null;
    notifyListeners();
    if (clearHistory) clearSession(notify: false);
    try {
      _client = _clientFactory(
        model: selectedModel ?? '',
        baseUrl: host,
        options: inference,
      );
      await _client!.testConnection();
      models = List.unmodifiable(await _client!.listModels());
      if (models.isEmpty) {
        throw const OllamaException(
          'Nenhum modelo instalado. Execute ollama pull <modelo>.',
        );
      }
      runningModels = List.unmodifiable(
        await _client!.listRunningModels(installed: models),
      );
      final currentModel = selectedModel;
      if (currentModel == null ||
          !models.any((model) => model.name == currentModel)) {
        selectedModel = models.first.name;
        _client = _clientFactory(
          model: selectedModel!,
          baseUrl: host,
          options: inference,
        );
      }
      _rebuildSession();
      _updateModelState();
      connectionState = OllamaConnectionState.ready;
    } catch (error) {
      connectionState = OllamaConnectionState.failed;
      connectionError = _errorText(error);
      notifyListeners();
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _refreshRunningModels() async {
    runningModels = List.unmodifiable(
      await _client!.listRunningModels(installed: models),
    );
  }

  void _updateModelState() {
    final model = selectedModel;
    final running =
        model != null &&
        runningModels.any((candidate) => candidate.name == model);
    modelState = running ? ModelRunState.running : ModelRunState.stopped;
  }

  void _rebuildSession() {
    final client = _client;
    final model = selectedModel;
    if (client == null || model == null) {
      _session = null;
      return;
    }
    _session = AgentSession(
      client: client,
      root: root,
      permissions: permissions,
      onToolResult: (call, result) {
        activities.insert(0, ToolActivity(call, result, happenedAt: _clock()));
        notifyListeners();
      },
    );
  }

  Future<void> _persist() => _store.save(
    DesktopPersistedState(
      host: host,
      model: selectedModel,
      inference: inference,
      permissions: permissions,
      activeRoot: root.path,
      recentRoots: recentRoots,
      sessions: sessions,
    ),
  );

  String _errorText(Object error) => switch (error) {
    FormatException() => error.message,
    SocketException() =>
      'Não foi possível conectar ao Ollama: ${error.message}',
    OllamaException() => 'Erro do Ollama: ${error.message}',
    AgentException() => 'Erro do agente: ${error.message}',
    FileSystemException() => error.message,
    _ => error.toString(),
  };
}

OllamaClient _defaultClientFactory({
  required String model,
  required Uri baseUrl,
  required InferenceOptions options,
}) => OllamaClient(model: model, baseUrl: baseUrl, options: options);
