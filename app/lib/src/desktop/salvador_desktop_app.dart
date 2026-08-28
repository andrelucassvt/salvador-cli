import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_controller.dart';
import 'desktop_state_store.dart';

const _navy = Color(0xFF103B54);
const _deepNavy = Color(0xFF082C40);
const _ocean = Color(0xFF147D92);
const _coral = Color(0xFFED6A5A);
const _shell = Color(0xFFF4F1EA);
const _paper = Color(0xFFFFFDF8);
const _ink = Color(0xFF172A33);
const _muted = Color(0xFF687980);
const _line = Color(0xFFDDE2DE);

const _titleBarHeight = 38.0;
const _topBarHeight = 62.0;
const _panelWidth = 286.0;
const _railWidth = 50.0;

class SalvadorDesktopApp extends StatelessWidget {
  const SalvadorDesktopApp({super.key, this.controller});

  final DesktopController? controller;

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
        fontFamily: 'Archivo',
        dividerColor: _line,
        dialogTheme: DialogThemeData(
          backgroundColor: _paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(_paper),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: _line),
              ),
            ),
          ),
        ),
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
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _ocean,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _ocean,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? _ocean : null,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : null,
          ),
        ),
        dividerTheme: const DividerThemeData(color: _line, thickness: 1),
      ),
      home: _ShellScreen(controller: controller),
    );
  }
}

class _ShellScreen extends StatefulWidget {
  const _ShellScreen({this.controller});

  final DesktopController? controller;

  @override
  State<_ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<_ShellScreen> {
  late final DesktopController _controller;
  late final bool _ownsController;
  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final _scrollController = ScrollController();
  List<String> _suggestions = const [];
  int _messageCount = 0;
  bool _panelExpanded = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? DesktopController();
    _controller.addListener(_handleControllerChange);
    _promptController.addListener(_updateSuggestions);
    if (_ownsController) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.initialize();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    if (_ownsController) _controller.dispose();
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

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _MacTitleBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_panelExpanded)
                  SizedBox(
                    width: _panelWidth,
                    child: _ActivityPanel(
                      controller: _controller,
                      onCollapse: () => setState(() => _panelExpanded = false),
                    ),
                  )
                else
                  SizedBox(
                    width: _railWidth,
                    child: _ActivityRail(
                      controller: _controller,
                      onExpand: () => setState(() => _panelExpanded = true),
                    ),
                  ),
                Expanded(child: _buildWorkspace()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Column(
      children: [
        _WorkspaceTopBar(
          controller: _controller,
          onOpenSettings: _openSettings,
        ),
        if (_controller.connectionError != null)
          _ErrorBanner(message: _controller.connectionError!),
        Expanded(
          child: _controller.messages.isEmpty
              ? _EmptyState(
                  ready:
                      _controller.connectionState ==
                      OllamaConnectionState.ready,
                  rootPath: _controller.root.path,
                  onPrompt: (text) {
                    _promptController.text = text;
                    _promptController.selection = TextSelection.collapsed(
                      offset: text.length,
                    );
                    _promptFocus.requestFocus();
                  },
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 18),
                  itemCount:
                      _controller.messages.length +
                      (_controller.isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _controller.messages.length) {
                      return const _ThinkingCard();
                    }
                    return _MessageCard(entry: _controller.messages[index]);
                  },
                ),
        ),
        _Composer(
          controller: _promptController,
          focusNode: _promptFocus,
          suggestions: _suggestions,
          sending: _controller.isSending,
          ready:
              _controller.connectionState == OllamaConnectionState.ready &&
              _controller.modelState == ModelRunState.running,
          onSuggestion: _insertSuggestion,
          onMention: _startMention,
          onSend: _send,
        ),
      ],
    );
  }
}

class _MacTitleBar extends StatelessWidget {
  const _MacTitleBar();

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    if (!isMac) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('mac-title-bar'),
      height: _titleBarHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async {
          final maximized = await windowManager.isMaximized();
          if (maximized) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
        child: Container(
          color: _deepNavy,
          padding: const EdgeInsets.only(left: 78, right: 16),
          alignment: Alignment.centerLeft,
          child: const Text(
            'SALVADOR',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTopBar extends StatelessWidget {
  const _WorkspaceTopBar({
    required this.controller,
    required this.onOpenSettings,
  });

  final DesktopController controller;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 960;
        final veryCompact = constraints.maxWidth < 700;
        return Container(
          key: const Key('workspace-top-bar'),
          height: _topBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            color: _paper,
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              if (!compact) ...[const _LogoMark(), const SizedBox(width: 10)],
              Expanded(child: _FolderMenu(controller: controller)),
              const SizedBox(width: 6),
              Expanded(child: _ModelMenu(controller: controller)),
              const SizedBox(width: 8),
              _StartStopButton(controller: controller, iconOnly: veryCompact),
              const Spacer(),
              if (veryCompact)
                IconButton(
                  key: const Key('new-session-button'),
                  tooltip: 'Nova sessão',
                  onPressed: controller.messages.isEmpty
                      ? null
                      : () => controller.newSession(),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                )
              else
                TextButton.icon(
                  key: const Key('new-session-button'),
                  onPressed: controller.messages.isEmpty
                      ? null
                      : () => controller.newSession(),
                  icon: const Icon(Icons.add_comment_outlined, size: 17),
                  label: const Text('Nova sessão'),
                ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('open-settings-button'),
                tooltip: 'Configurações',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.tune_rounded, size: 19),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: _coral,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white,
            size: 21,
          ),
        ),
        const SizedBox(width: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 120) return const SizedBox.shrink();
            return const Text(
              'SALVADOR',
              style: TextStyle(
                color: _navy,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FolderMenu extends StatelessWidget {
  const _FolderMenu({required this.controller});

  final DesktopController controller;

  String get _shortPath {
    final parts = controller.root.path
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 2) return controller.root.path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final recents = controller.recentRoots;
    return MenuAnchor(
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Pasta do projeto',
                  style: TextStyle(
                    color: _ink.withValues(alpha: .55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...recents.map(
                (path) => _FolderMenuItem(
                  path: path,
                  active: path == controller.root.path,
                  onTap: () => controller.selectRoot(path),
                ),
              ),
              if (recents.isNotEmpty) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: MenuItemButton(
                  onPressed: () async {
                    final selected = await getDirectoryPath(
                      initialDirectory: controller.root.path,
                      confirmButtonText: 'Usar esta pasta',
                    );
                    if (selected != null) await controller.selectRoot(selected);
                  },
                  leadingIcon: const Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: _ocean,
                  ),
                  child: const Text('Escolher outra pasta…'),
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, menuController, _) => InkWell(
        key: const Key('folder-menu'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => menuController.isOpen
            ? menuController.close()
            : menuController.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_outlined, size: 16, color: _muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _shortPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_drop_down_rounded,
                size: 17,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderMenuItem extends StatelessWidget {
  const _FolderMenuItem({
    required this.path,
    required this.active,
    required this.onTap,
  });

  final String path;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: active ? _ocean : _line,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  color: active ? _ink : _muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelMenu extends StatelessWidget {
  const _ModelMenu({required this.controller});

  final DesktopController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedModel;
    final running = controller.runningModels
        .where((model) => model.name == selected)
        .toList();
    final isRunning = running.isNotEmpty;
    return MenuAnchor(
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...controller.models.map(
                (model) => _ModelMenuItem(
                  model: model,
                  selected: model.name == selected,
                  running: controller.runningModels.any(
                    (runningModel) => runningModel.name == model.name,
                  ),
                  knownVram: controller.runningModels
                      .where((runningModel) => runningModel.name == model.name)
                      .map((runningModel) => runningModel.sizeVramBytes)
                      .where((bytes) => bytes > 0)
                      .fold<int?>(null, (_, bytes) => bytes),
                  contextFuture: model.name == selected
                      ? controller.fetchModelContext(model.name)
                      : null,
                  onTap: () => controller.selectModel(model.name),
                ),
              ),
              const Divider(height: 1),
              FutureBuilder<int?>(
                future: controller.availableMemory(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Text(
                      bytes == null
                          ? 'RAM livre do sistema: indisponível'
                          : 'RAM livre do sistema: ${_formatBytes(bytes)}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
      builder: (context, menuController, _) => InkWell(
        key: const Key('model-menu'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => menuController.isOpen
            ? menuController.close()
            : menuController.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF7BD8B0) : _line,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  selected ?? 'Sem modelo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_drop_down_rounded,
                size: 17,
                color: _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelMenuItem extends StatelessWidget {
  const _ModelMenuItem({
    required this.model,
    required this.selected,
    required this.running,
    required this.knownVram,
    required this.contextFuture,
    required this.onTap,
  });

  final OllamaModelInfo model;
  final bool selected;
  final bool running;
  final int? knownVram;
  final Future<int?>? contextFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('model-item-${model.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: selected ? _ocean : _line,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 12.5,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _StatusPill(running: running),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '${_formatBytes(model.sizeBytes)} · ${model.quantization ?? model.family ?? 'peso desconhecido'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (contextFuture != null)
                    FutureBuilder<int?>(
                      future: contextFuture,
                      builder: (context, snapshot) {
                        final contextLength = snapshot.data;
                        if (contextLength == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            'contexto: $contextLength tokens',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (knownVram != null)
              Text(
                '${_formatBytes(knownVram!)} em VRAM',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.running});

  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: running ? const Color(0xFFE2F5EC) : const Color(0xFFEFF2F0),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        running ? 'CARREGADO' : 'PARADO',
        style: TextStyle(
          color: running ? const Color(0xFF2E7D57) : _muted,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _StartStopButton extends StatelessWidget {
  const _StartStopButton({required this.controller, this.iconOnly = false});

  final DesktopController controller;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final starting = controller.modelState == ModelRunState.starting;
    final running = controller.modelState == ModelRunState.running;
    final busy = starting || controller.isSending;
    final enabled =
        controller.connectionState == OllamaConnectionState.ready &&
        controller.selectedModel != null &&
        !busy;

    final Widget content;
    if (starting) {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _ocean),
          ),
          SizedBox(width: 8),
          Text('Aguarde…'),
        ],
      );
    } else if (running) {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stop_rounded, size: 16),
          SizedBox(width: 6),
          Text('Encerrar modelo'),
        ],
      );
    } else {
      content = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: 17),
          SizedBox(width: 4),
          Text('Iniciar modelo'),
        ],
      );
    }

    if (iconOnly) {
      return Tooltip(
        message: running ? 'Encerrar modelo' : 'Iniciar modelo',
        child: OutlinedButton(
          key: const Key('start-stop-button'),
          onPressed: enabled
              ? () => running ? controller.stopModel() : controller.startModel()
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _navy,
            side: const BorderSide(color: _line),
            padding: const EdgeInsets.all(9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: starting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _ocean,
                  ),
                )
              : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
        ),
      );
    }

    return OutlinedButton(
      key: const Key('start-stop-button'),
      onPressed: enabled
          ? () => running ? controller.stopModel() : controller.startModel()
          : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: _navy,
        side: const BorderSide(color: _line),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: content,
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});

  final DesktopController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _hostController;
  late final TextEditingController _contextController;
  late double _temperature;
  Duration? _keepAlive;
  Duration? _timeout;
  late bool _allowEdit;
  late bool _allowCommands;
  bool _testing = false;
  bool _saving = false;
  HostTestResult? _testResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _hostController = TextEditingController(text: controller.host.toString());
    _contextController = TextEditingController(
      text: controller.contextLength?.toString() ?? '',
    );
    _temperature = controller.temperature;
    _keepAlive = controller.keepAlive;
    _timeout = controller.timeout;
    _allowEdit = controller.allowEdit;
    _allowCommands = controller.allowCommands;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
    });
    final result = await widget.controller.testHost(_hostController.text);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveSettings(
        hostText: _hostController.text,
        temperature: _temperature,
        contextLength: int.tryParse(_contextController.text.trim()),
        keepAlive: _keepAlive,
        timeout: _timeout,
        allowEdit: _allowEdit,
        allowCommands: _allowCommands,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is FormatException
            ? error.message
            : error is OllamaException
            ? error.message
            : error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('settings-dialog'),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: viewport.height * .82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Configurações',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _DialogLabel('SERVIDOR OLLAMA'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('settings-host-field'),
                            controller: _hostController,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'JetBrains Mono',
                            ),
                            decoration: const InputDecoration(
                              hintText: 'http://127.0.0.1:11434',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          key: const Key('test-host-button'),
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox.square(
                                  dimension: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.wifi_tethering_rounded,
                                  size: 16,
                                ),
                          label: const Text('Testar'),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _testResult!.ok
                            ? 'Servidor ok · ${_testResult!.latency!.inMilliseconds} ms · ${_testResult!.modelCount} modelo(s) instalado(s)'
                            : 'Falha no teste: ${_testResult!.error}',
                        key: const Key('host-test-result'),
                        style: TextStyle(
                          color: _testResult!.ok
                              ? const Color(0xFF2E7D57)
                              : _coral,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const _DialogLabel('INFERÊNCIA'),
                    const SizedBox(height: 10),
                    _SliderSetting(
                      label: 'Temperatura',
                      value: _temperature,
                      onChanged: (value) =>
                          setState(() => _temperature = value),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const Key('settings-context-field'),
                      controller: _contextController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'JetBrains Mono',
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tamanho do contexto',
                        hintText: 'Padrão do modelo',
                        suffixText: 'tokens',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Duration?>(
                      key: const Key('settings-keep-alive-field'),
                      initialValue: _keepAlive,
                      decoration: const InputDecoration(
                        labelText: 'Keep-alive',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Padrão do Ollama (5 min)'),
                        ),
                        DropdownMenuItem(
                          value: Duration(minutes: 30),
                          child: Text('30 minutos'),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 1),
                          child: Text('1 hora'),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 4),
                          child: Text('4 horas'),
                        ),
                        DropdownMenuItem(
                          value: Duration(hours: 24),
                          child: Text('24 horas'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _keepAlive = value),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<Duration?>(
                      key: const Key('settings-timeout-field'),
                      initialValue: _timeout,
                      decoration: const InputDecoration(
                        labelText: 'Timeout das requisições',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: null,
                          child: Text('Sem limite'),
                        ),
                        DropdownMenuItem(
                          value: Duration(seconds: 30),
                          child: Text('30 segundos'),
                        ),
                        DropdownMenuItem(
                          value: Duration(seconds: 60),
                          child: Text('60 segundos'),
                        ),
                        DropdownMenuItem(
                          value: Duration(seconds: 120),
                          child: Text('120 segundos'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _timeout = value),
                    ),
                    const SizedBox(height: 20),
                    const _DialogLabel('PERMISSÕES'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      key: const Key('settings-allow-edit'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Editar arquivos',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: const Text(
                        'Permite write_file e replace_in_file na pasta do projeto.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _allowEdit,
                      onChanged: (value) => setState(() => _allowEdit = value),
                    ),
                    SwitchListTile(
                      key: const Key('settings-allow-commands'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Executar comandos',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: const Text(
                        'Permite run_command na pasta do projeto.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _allowCommands,
                      onChanged: (value) =>
                          setState(() => _allowCommands = value),
                    ),
                    const SwitchListTile(
                      key: Key('settings-network-access'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Acesso à rede',
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        'Desabilitado: run_command executa sem sandbox de rede, então o agente sempre pode alcançar a internet.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: false,
                      onChanged: null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        key: const Key('settings-error'),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE9E5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _ink, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('settings-cancel-button'),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('settings-save-button'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('Salvar e reconectar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: _ink, fontSize: 13.5),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, 1),
            min: 0,
            max: 1,
            divisions: 20,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.controller, required this.onCollapse});

  final DesktopController controller;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final currentSession = controller.currentSessionSummary;
    final sessions = controller.sessions;
    return Container(
      key: const Key('activity-panel'),
      decoration: const BoxDecoration(color: _deepNavy),
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _AzulejoPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('collapse-panel-button'),
                      tooltip: 'Recolher painel',
                      onPressed: onCollapse,
                      icon: const Icon(
                        Icons.menu_open_rounded,
                        color: Colors.white70,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      'ATIVIDADE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${controller.activities.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: controller.activities.isEmpty
                      ? const _NoActivity()
                      : ListView.separated(
                          itemCount: controller.activities.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 7),
                          itemBuilder: (_, index) => _ActivityTile(
                            activity: controller.activities[index],
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'SESSÕES',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: (sessions.isEmpty && currentSession == null)
                      ? const Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'As sessões encerradas aparecerão aqui.',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            if (currentSession != null)
                              _SessionTile(
                                session: currentSession,
                                current: true,
                              ),
                            ...sessions.map(
                              (session) => _SessionTile(
                                session: session,
                                current: false,
                              ),
                            ),
                          ],
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

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.current});

  final PersistedSessionSummary session;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: current ? _coral : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatSessionDate(session.startedAt)} · ${session.actionCount} ações',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 9.5,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: _coral,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({required this.controller, required this.onExpand});

  final DesktopController controller;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('activity-rail'),
      decoration: const BoxDecoration(color: _deepNavy),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            key: const Key('expand-panel-button'),
            tooltip: 'Expandir painel',
            onPressed: onExpand,
            icon: const Icon(
              Icons.menu_rounded,
              color: Colors.white70,
              size: 19,
            ),
          ),
          const SizedBox(height: 10),
          _RailIcon(
            key: const Key('rail-activity-button'),
            icon: Icons.monitor_heart_outlined,
            badge: controller.activities.isEmpty
                ? null
                : '${controller.activities.length}',
            onTap: onExpand,
          ),
          const SizedBox(height: 8),
          _RailIcon(
            key: const Key('rail-sessions-button'),
            icon: Icons.history_rounded,
            badge:
                (controller.sessions.isNotEmpty ||
                    controller.currentSessionSummary != null)
                ? '${controller.sessions.length + (controller.currentSessionSummary != null ? 1 : 0)}'
                : null,
            onTap: onExpand,
          ),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: Colors.white60, size: 19),
            if (badge != null)
              Positioned(
                right: -12,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _coral,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
                                        fontFamily: 'JetBrains Mono',
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
                        final shiftPressed =
                            HardwareKeyboard.instance.isShiftPressed;
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !shiftPressed) {
                          onSend();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const Key('composer-field'),
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
                              : 'Conecte ao Ollama e inicie o modelo para começar…',
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
                            'Enter para enviar · Shift+Enter para quebrar linha',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: _muted, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          key: const Key('send-button'),
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
  const _EmptyState({
    required this.ready,
    required this.rootPath,
    required this.onPrompt,
  });

  final bool ready;
  final String rootPath;
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
                    ? 'O agente pode ler, editar e executar comandos somente em $rootPath.'
                    : 'Confirme o servidor, a pasta e o modelo para começar.',
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
                fontFamily: 'JetBrains Mono',
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

  ({String badge, String title, Color color}) get _style =>
      switch (activity.call.name) {
        'read_file' => (
          badge: 'R',
          title: 'Leitura',
          color: const Color(0xFF74C9D3),
        ),
        'write_file' => (
          badge: 'W',
          title: 'Gravação',
          color: const Color(0xFF7BD8B0),
        ),
        'replace_in_file' => (
          badge: 'E',
          title: 'Edição',
          color: const Color(0xFFFFCF70),
        ),
        'run_command' => (
          badge: '\$',
          title: 'Comando',
          color: const Color(0xFFF29E8E),
        ),
        _ => (badge: '?', title: activity.call.name, color: Colors.white54),
      };

  String get _detail {
    final result = activity.result;
    final measurable =
        result.startsWith('OK:') ||
        result.startsWith('ERRO:') ||
        result.contains('EXIT_CODE:');
    if (measurable) return result.split('\n').first;
    return activity.summary;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              style.badge,
              style: TextStyle(
                color: style.color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        style.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _relativeTime(activity.happenedAt),
                      style: const TextStyle(
                        color: Color(0x75FFFFFF),
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x75FFFFFF),
                    fontSize: 9,
                    fontFamily: 'JetBrains Mono',
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
          fontFamily: 'JetBrains Mono',
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

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'n/d';
  final gb = bytes / 1024 / 1024 / 1024;
  if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return '${diff.inMinutes} min';
  if (diff.inDays < 1) return '${diff.inHours} h';
  return '${diff.inDays} d';
}

String _formatSessionDate(DateTime date) {
  final now = DateTime.now();
  final sameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  if (sameDay) {
    return 'hoje ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
