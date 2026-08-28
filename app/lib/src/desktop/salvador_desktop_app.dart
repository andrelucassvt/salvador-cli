import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:salvador_cli/salvador_cli.dart';

import 'desktop_controller.dart';

const _navy = Color(0xFF103B54);
const _deepNavy = Color(0xFF082C40);
const _ocean = Color(0xFF147D92);
const _coral = Color(0xFFED6A5A);
const _shell = Color(0xFFF4F1EA);
const _paper = Color(0xFFFFFDF8);
const _ink = Color(0xFF172A33);
const _muted = Color(0xFF687980);
const _line = Color(0xFFDDE2DE);

class SalvadorDesktopApp extends StatelessWidget {
  const SalvadorDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _ocean,
      brightness: Brightness.light,
      surface: _paper,
    );
    return MaterialApp(
      title: 'Salvador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _shell,
        fontFamily: Platform.isMacOS ? 'Avenir Next' : 'Segoe UI',
        dividerColor: _line,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _paper,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _ocean, width: 1.5),
          ),
        ),
      ),
      home: const _WorkspaceScreen(),
    );
  }
}

class _WorkspaceScreen extends StatefulWidget {
  const _WorkspaceScreen();

  @override
  State<_WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<_WorkspaceScreen> {
  late final DesktopController _controller;
  late final TextEditingController _hostController;
  late final TextEditingController _rootController;
  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final _scrollController = ScrollController();
  List<String> _suggestions = const [];
  int _messageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = DesktopController();
    _hostController = TextEditingController(text: _controller.host.toString());
    _rootController = TextEditingController(text: _controller.root.path);
    _controller.addListener(_handleControllerChange);
    _promptController.addListener(_updateSuggestions);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.initialize(),
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChange)
      ..dispose();
    _hostController.dispose();
    _rootController.dispose();
    _promptController.dispose();
    _promptFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) return;
    final shouldScroll = _messageCount != _controller.messages.length;
    _messageCount = _controller.messages.length;
    setState(() {});
    if (shouldScroll || _controller.isSending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _updateSuggestions() {
    final selection = _promptController.selection;
    final cursor = selection.isValid ? selection.extentOffset : 0;
    final next = _controller.fileSuggestions(_promptController.text, cursor);
    if (next.toString() == _suggestions.toString()) return;
    setState(() => _suggestions = next);
  }

  Future<void> _send() async {
    final text = _promptController.text;
    if (text.trim().isEmpty || _controller.isSending) return;
    if (text.trim() == '/exit' || text.trim() == '/quit') {
      await SystemNavigator.pop();
      return;
    }
    _promptController.clear();
    await _controller.send(text);
    if (mounted) _promptFocus.requestFocus();
  }

  void _insertSuggestion(String path) {
    final oldText = _promptController.text;
    final oldCursor = _promptController.selection.extentOffset;
    final newText = _controller.insertMention(oldText, oldCursor, path);
    final newCursor = (oldCursor + newText.length - oldText.length).clamp(
      0,
      newText.length,
    );
    _promptController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _promptFocus.requestFocus();
  }

  void _startMention() {
    final value = _promptController.value;
    final prefix = value.text.isEmpty || value.text.endsWith(' ') ? '@' : ' @';
    final text = '${value.text}$prefix';
    _promptController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _promptFocus.requestFocus();
  }

  Future<void> _chooseRoot() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _DirectoryPicker(initialPath: _rootController.text),
    );
    if (selected != null) _rootController.text = selected;
  }

  Future<void> _connect() => _controller.refreshConnection(
    hostText: _hostController.text,
    rootPath: _rootController.text,
  );

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _paper,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .82,
          child: _SessionPanel(
            controller: _controller,
            hostController: _hostController,
            rootController: _rootController,
            onChooseRoot: _chooseRoot,
            onConnect: () async {
              await _connect();
              if (context.mounted &&
                  _controller.connectionState == OllamaConnectionState.ready) {
                Navigator.pop(context);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidebar = constraints.maxWidth >= 980;
          return Row(
            children: [
              if (showSidebar)
                SizedBox(
                  width: 306,
                  child: _SessionPanel(
                    controller: _controller,
                    hostController: _hostController,
                    rootController: _rootController,
                    onChooseRoot: _chooseRoot,
                    onConnect: _connect,
                  ),
                ),
              Expanded(
                child: _ChatWorkspace(
                  controller: _controller,
                  promptController: _promptController,
                  promptFocus: _promptFocus,
                  scrollController: _scrollController,
                  suggestions: _suggestions,
                  onSuggestion: _insertSuggestion,
                  onMention: _startMention,
                  onSend: _send,
                  onShowSettings: showSidebar ? null : _showSettings,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.controller,
    required this.hostController,
    required this.rootController,
    required this.onChooseRoot,
    required this.onConnect,
  });

  final DesktopController controller;
  final TextEditingController hostController;
  final TextEditingController rootController;
  final VoidCallback onChooseRoot;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _deepNavy),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AzulejoPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: 32),
                _SideLabel(
                  text: 'SESSÃO LOCAL',
                  trailing: _ConnectionDot(state: controller.connectionState),
                ),
                const SizedBox(height: 12),
                _DarkField(
                  label: 'Servidor Ollama',
                  controller: hostController,
                  hint: 'http://127.0.0.1:11434',
                ),
                const SizedBox(height: 12),
                _DarkField(
                  label: 'Pasta do projeto',
                  controller: rootController,
                  suffix: IconButton(
                    tooltip: 'Escolher pasta',
                    onPressed: onChooseRoot,
                    icon: const Icon(Icons.folder_open_rounded, size: 19),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(controller.selectedModel),
                  initialValue:
                      controller.models.contains(controller.selectedModel)
                      ? controller.selectedModel
                      : null,
                  dropdownColor: _navy,
                  iconEnabledColor: Colors.white70,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _darkDecoration('Modelo'),
                  items: controller.models
                      .map(
                        (model) => DropdownMenuItem(
                          value: model,
                          child: Text(model, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: controller.selectModel,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      controller.connectionState ==
                          OllamaConnectionState.loading
                      ? null
                      : onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: _coral,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _coral.withValues(alpha: .45),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon:
                      controller.connectionState ==
                          OllamaConnectionState.loading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(
                    controller.connectionState == OllamaConnectionState.ready
                        ? 'Atualizar conexão'
                        : 'Conectar ao Ollama',
                  ),
                ),
                const SizedBox(height: 26),
                _SideLabel(
                  text: 'ATIVIDADE DO AGENTE',
                  trailing: Text(
                    '${controller.activities.length}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: controller.activities.isEmpty
                      ? const _NoActivity()
                      : ListView.separated(
                          itemCount: controller.activities.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, index) => _ActivityTile(
                            activity: controller.activities[index],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatWorkspace extends StatelessWidget {
  const _ChatWorkspace({
    required this.controller,
    required this.promptController,
    required this.promptFocus,
    required this.scrollController,
    required this.suggestions,
    required this.onSuggestion,
    required this.onMention,
    required this.onSend,
    this.onShowSettings,
  });

  final DesktopController controller;
  final TextEditingController promptController;
  final FocusNode promptFocus;
  final ScrollController scrollController;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onMention;
  final VoidCallback onSend;
  final VoidCallback? onShowSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(controller: controller, onShowSettings: onShowSettings),
        if (controller.connectionError != null)
          _ErrorBanner(message: controller.connectionError!),
        Expanded(
          child: controller.messages.isEmpty
              ? _EmptyState(
                  ready:
                      controller.connectionState == OllamaConnectionState.ready,
                  onPrompt: (text) {
                    promptController.text = text;
                    promptController.selection = TextSelection.collapsed(
                      offset: text.length,
                    );
                    promptFocus.requestFocus();
                  },
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 18),
                  itemCount:
                      controller.messages.length +
                      (controller.isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == controller.messages.length) {
                      return const _ThinkingCard();
                    }
                    return _MessageCard(entry: controller.messages[index]);
                  },
                ),
        ),
        _Composer(
          controller: promptController,
          focusNode: promptFocus,
          suggestions: suggestions,
          sending: controller.isSending,
          ready: controller.connectionState == OllamaConnectionState.ready,
          onSuggestion: onSuggestion,
          onMention: onMention,
          onSend: onSend,
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, this.onShowSettings});

  final DesktopController controller;
  final VoidCallback? onShowSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _paper,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (onShowSettings != null) ...[
            IconButton(
              tooltip: 'Configurar sessão',
              onPressed: onShowSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.selectedModel ?? 'Agente local',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  controller.root.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: controller.messages.isEmpty
                ? null
                : controller.clearSession,
            icon: const Icon(Icons.add_comment_outlined, size: 17),
            label: const Text('Nova sessão'),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
    required this.sending,
    required this.ready,
    required this.onSuggestion,
    required this.onMention,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final bool sending;
  final bool ready;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onMention;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      color: _shell,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    color: _paper,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14082C40),
                        blurRadius: 18,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Column(
                    children: suggestions
                        .map(
                          (path) => InkWell(
                            onTap: () => onSuggestion(path),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.description_outlined,
                                    color: _ocean,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      path,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: _paper,
                  border: Border.all(color: ready ? _line : _coral),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12082C40),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Focus(
                      onKeyEvent: (_, event) {
                        final modifier =
                            HardwareKeyboard.instance.isMetaPressed ||
                            HardwareKeyboard.instance.isControlPressed;
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            modifier) {
                          onSend();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 2,
                        maxLines: 6,
                        enabled: !sending,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          height: 1.45,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: ready
                              ? 'Peça uma alteração ou mencione um arquivo com @…'
                              : 'Conecte ao Ollama para começar…',
                          hintStyle: const TextStyle(color: _muted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: sending ? null : onMention,
                          icon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 17,
                          ),
                          label: const Text('Arquivo'),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '⌘/Ctrl + Enter para enviar',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: sending || !ready ? null : onSend,
                          style: FilledButton.styleFrom(
                            backgroundColor: _ocean,
                            minimumSize: const Size(46, 40),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: sending
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.ready, required this.onPrompt});

  final bool ready;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.circular(21),
                ),
                child: const Icon(
                  Icons.terminal_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                ready
                    ? 'Pronto para trabalhar localmente.'
                    : 'Prepare sua bancada local.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ready
                    ? 'O agente pode ler, editar e executar comandos somente na pasta selecionada.'
                    : 'Confirme o servidor, a pasta e o modelo no painel de sessão.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (ready) ...[
                const SizedBox(height: 30),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _PromptCard(
                      label: 'Entender o projeto',
                      prompt:
                          'Analise este projeto e explique sua arquitetura.',
                      icon: Icons.account_tree_outlined,
                      onTap: onPrompt,
                    ),
                    _PromptCard(
                      label: 'Revisar um arquivo',
                      prompt: 'Revise @',
                      icon: Icons.fact_check_outlined,
                      onTap: onPrompt,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final user = entry.role == ChatRole.user;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: user ? 700 : 880),
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: user ? _navy : _paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(user ? 15 : 4),
            bottomRight: Radius.circular(user ? 4 : 15),
          ),
          border: user ? null : Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'VOCÊ' : 'SALVADOR',
              style: TextStyle(
                color: user ? Colors.white60 : _ocean,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              entry.content,
              style: TextStyle(
                color: user ? Colors.white : _ink,
                fontSize: 14,
                height: 1.52,
              ),
            ),
            if (entry.mentionedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: entry.mentionedFiles
                    .map((path) => _FileChip(path: path))
                    .toList(growable: false),
              ),
            ],
            if (entry.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...entry.warnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Aviso: $warning',
                    style: const TextStyle(color: _coral, fontSize: 11),
                  ),
                ),
              ),
            ],
            if (entry.metrics != null) ...[
              const SizedBox(height: 14),
              _MetricsBar(metrics: entry.metrics!),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricsBar extends StatelessWidget {
  const _MetricsBar({required this.metrics});

  final InferenceMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final rate = metrics.tokensPerSecond;
    final items = [
      '${rate == null ? 'n/d' : rate.toStringAsFixed(1)} tok/s',
      '${metrics.generatedTokens} saída',
      '${metrics.promptTokens} entrada',
      '${metrics.totalSeconds.toStringAsFixed(2)}s total',
      if (metrics.generations > 1) '${metrics.generations} gerações',
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 5,
      children: items
          .map(
            (item) => Text(
              item,
              style: const TextStyle(
                color: _muted,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _ocean),
            ),
            SizedBox(width: 10),
            Text('O agente está trabalhando…', style: TextStyle(color: _muted)),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: const Color(0xFFFFE9E5),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _coral, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: _ink, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: _coral, shape: BoxShape.circle),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
        ),
        SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SALVADOR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            Text(
              'AGENTE LOCAL',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SideLabel extends StatelessWidget {
  const _SideLabel({required this.text, required this.trailing});

  final String text;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.35,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.state});

  final OllamaConnectionState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      OllamaConnectionState.ready => const Color(0xFF7BD8B0),
      OllamaConnectionState.loading => const Color(0xFFFFCF70),
      OllamaConnectionState.failed => _coral,
      OllamaConnectionState.idle => Colors.white38,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.label,
    required this.controller,
    this.hint,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 12),
      decoration: _darkDecoration(label).copyWith(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        suffixIcon: suffix,
        suffixIconColor: Colors.white60,
      ),
    );
  }
}

InputDecoration _darkDecoration(String label) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
  filled: true,
  fillColor: Colors.white.withValues(alpha: .07),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: BorderSide(color: Colors.white.withValues(alpha: .13)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: _ocean, width: 1.5),
  ),
);

class _NoActivity extends StatelessWidget {
  const _NoActivity();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'As leituras, edições e comandos aparecerão aqui.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.45),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final ToolActivity activity;

  @override
  Widget build(BuildContext context) {
    final icon = switch (activity.call.name) {
      'read_file' => Icons.visibility_outlined,
      'write_file' => Icons.note_add_outlined,
      'replace_in_file' => Icons.edit_note_rounded,
      'run_command' => Icons.terminal_rounded,
      _ => Icons.build_outlined,
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF74C9D3), size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.call.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activity.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x75FFFFFF),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.label,
    required this.prompt,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String prompt;
  final IconData icon;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => onTap(prompt),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: _navy,
        backgroundColor: _paper,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2F3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '@$path',
        style: const TextStyle(
          color: _ocean,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _AzulejoPainter extends CustomPainter {
  const _AzulejoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .026)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const tile = 54.0;
    for (double y = -tile; y < size.height + tile; y += tile) {
      for (double x = -tile; x < size.width + tile; x += tile) {
        final center = Offset(x + tile / 2, y + tile / 2);
        final diamond = Path()
          ..moveTo(center.dx, center.dy - 13)
          ..lineTo(center.dx + 13, center.dy)
          ..lineTo(center.dx, center.dy + 13)
          ..lineTo(center.dx - 13, center.dy)
          ..close();
        canvas.drawPath(diamond, paint);
        canvas.drawCircle(center, 4, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DirectoryPicker extends StatefulWidget {
  const _DirectoryPicker({required this.initialPath});

  final String initialPath;

  @override
  State<_DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends State<_DirectoryPicker> {
  late Directory _current;
  List<Directory> _directories = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final candidate = Directory(widget.initialPath).absolute;
    _current = candidate.existsSync() ? candidate : Directory.current.absolute;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final directories = await _current
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
      directories.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      if (!mounted) return;
      setState(() => _directories = directories);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Directory directory) async {
    _current = directory.absolute;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _paper,
      title: const Text('Escolher pasta do projeto'),
      content: SizedBox(
        width: 620,
        height: 430,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _shell,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Pasta acima',
                    onPressed: _current.parent.path == _current.path
                        ? null
                        : () => _open(_current.parent),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  ),
                  Expanded(
                    child: SelectableText(
                      _current.path,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _directories.isEmpty
                  ? const Center(
                      child: Text('Esta pasta não contém subpastas.'),
                    )
                  : ListView.builder(
                      itemCount: _directories.length,
                      itemBuilder: (_, index) {
                        final directory = _directories[index];
                        final name = directory.uri.pathSegments
                            .where((part) => part.isNotEmpty)
                            .last;
                        return ListTile(
                          leading: const Icon(
                            Icons.folder_rounded,
                            color: _ocean,
                          ),
                          title: Text(name),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(directory),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _current.path),
          child: const Text('Usar esta pasta'),
        ),
      ],
    );
  }
}
