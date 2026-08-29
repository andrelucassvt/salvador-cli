import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/config/inject/app_injector.dart';
import 'package:salvador_desktop/presentation/desktop/content/composer.dart';
import 'package:salvador_desktop/presentation/desktop/content/settings_dialog.dart';
import 'package:salvador_desktop/presentation/desktop/content/workspace_top_bar.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/activity_panel.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/chat_widgets.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/files_panel.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/preview_pane.dart';

class DesktopView extends StatelessWidget {
  const DesktopView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ocean,
      brightness: Brightness.light,
      surface: paper,
    );
    return MaterialApp(
      title: 'Salvador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: shell,
        fontFamily: 'Archivo',
        dividerColor: line,
        dialogTheme: DialogThemeData(
          backgroundColor: paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(paper),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: line),
              ),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: paper,
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ocean, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: ocean,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: ocean,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? ocean : null,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Colors.white : null,
          ),
        ),
        dividerTheme: const DividerThemeData(color: line, thickness: 1),
      ),
      home: const _ShellScreen(),
    );
  }
}

class _ShellScreen extends StatefulWidget {
  const _ShellScreen();

  @override
  State<_ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<_ShellScreen> {
  late final WorkspaceCubit _workspaceCubit;
  late final ChatCubit _chatCubit;
  late final FileExplorerCubit _fileExplorerCubit;
  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();
  final _scrollController = ScrollController();
  final _filterController = TextEditingController();
  List<String> _suggestions = const [];
  int _messageCount = 0;
  bool _panelExpanded = false;
  bool _rightPanelExpanded = false;

  @override
  void initState() {
    super.initState();
    _workspaceCubit = AppInjector.inject<WorkspaceCubit>();
    _chatCubit = AppInjector.inject<ChatCubit>();
    _fileExplorerCubit = AppInjector.inject<FileExplorerCubit>();
    _promptController.addListener(_updateSuggestions);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _workspaceCubit.initialize();
    });
  }

  @override
  void dispose() {
    _workspaceCubit.close();
    _chatCubit.close();
    _fileExplorerCubit.close();
    _promptController.dispose();
    _promptFocus.dispose();
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _updateSuggestions() {
    final selection = _promptController.selection;
    final cursor = selection.isValid ? selection.extentOffset : 0;
    final next = _fileExplorerCubit.fileSuggestions(
      _promptController.text,
      cursor,
    );
    if (next.toString() == _suggestions.toString()) return;
    setState(() => _suggestions = next);
  }

  Future<void> _send() async {
    final text = _promptController.text;
    if (text.trim().isEmpty) return;
    if (text.trim() == '/exit' || text.trim() == '/quit') {
      await SystemNavigator.pop();
      return;
    }
    final workspace = _workspaceCubit.state;
    if (workspace is WorkspaceReady &&
        workspace.modelState == WorkspaceModelState.stopped &&
        workspace.selectedModel != null &&
        !workspace.connecting) {
      await _workspaceCubit.startModel();
      final afterStart = _workspaceCubit.state;
      if (afterStart is! WorkspaceReady ||
          afterStart.modelState != WorkspaceModelState.running) {
        // Falha ao iniciar: o banner de erro ja mostra o motivo e o texto
        // digitado fica no composer para nova tentativa.
        return;
      }
      // A View e a dona da sincronizacao de readiness: afirma que o modelo
      // acabou de entrar em execucao sem depender da ordem de entrega do
      // BlocListener (que pode chegar depois desta chamada).
      _chatCubit.updateReadiness(true);
    }
    _promptController.clear();
    await _chatCubit.send(text);
    if (mounted) _promptFocus.requestFocus();
  }

  void _insertSuggestion(String path) {
    final oldText = _promptController.text;
    final oldCursor = _promptController.selection.extentOffset;
    final newText = _fileExplorerCubit.insertMention(oldText, oldCursor, path);
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

  Future<void> _attachFiles() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    _chatCubit.addAttachments(files.map((f) => f.path).toList());
  }

  void _mentionPreviewed() {
    final value = _promptController.value;
    final cursor = value.selection.isValid
        ? value.selection.extentOffset
        : value.text.length;
    final newText = _fileExplorerCubit.mentionPreviewedFile(value.text, cursor);
    if (newText == value.text) return;
    _promptController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _promptFocus.requestFocus();
  }

  Future<void> _openSettings() async {
    final workspaceState = _workspaceCubit.state;
    if (workspaceState is! WorkspaceReady) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BlocProvider<WorkspaceCubit>.value(
        value: _workspaceCubit,
        child: SettingsDialog(workspace: workspaceState),
      ),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<WorkspaceCubit>.value(value: _workspaceCubit),
        BlocProvider<ChatCubit>.value(value: _chatCubit),
        BlocProvider<FileExplorerCubit>.value(value: _fileExplorerCubit),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<WorkspaceCubit, WorkspaceState>(
            listenWhen: (previous, current) {
              if (current is! WorkspaceReady) return false;
              if (previous is! WorkspaceReady) return true;
              if (previous.connecting && !current.connecting) return true;
              return previous.root?.path != current.root?.path ||
                  previous.host != current.host ||
                  previous.selectedModel != current.selectedModel ||
                  previous.permissions != current.permissions;
            },
            listener: (context, state) {
              final ready = state as WorkspaceReady;
              if (ready.models.isEmpty || ready.selectedModel == null) return;
              _fileExplorerCubit.setRoot(ready.root);
              _chatCubit.attachSession(
                host: ready.host,
                model: ready.selectedModel!,
                options: ready.inference,
                root: ready.root,
                permissions: ready.permissions,
              );
            },
          ),
          BlocListener<WorkspaceCubit, WorkspaceState>(
            listenWhen: (previous, current) {
              if (current is! WorkspaceReady) return false;
              if (previous is! WorkspaceReady) return true;
              return previous.connecting != current.connecting ||
                  previous.modelState != current.modelState;
            },
            listener: (context, state) {
              final ready = state as WorkspaceReady;
              _chatCubit.updateReadiness(
                !ready.connecting &&
                    ready.selectedModel != null &&
                    ready.modelState != WorkspaceModelState.starting,
              );
            },
          ),
          BlocListener<ChatCubit, ChatState>(
            listener: (context, state) {
              final idle = state as ChatIdle;
              final shouldScroll = _messageCount != idle.messages.length;
              _messageCount = idle.messages.length;
              if (shouldScroll || idle.sending) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(),
                );
              }
            },
          ),
        ],
        child: Scaffold(
          body: Column(
            children: [
              const MacTitleBar(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_panelExpanded)
                      SizedBox(
                        width: panelWidth,
                        child: ActivityPanel(
                          onCollapse: () =>
                              setState(() => _panelExpanded = false),
                        ),
                      )
                    else
                      SizedBox(
                        width: railWidth,
                        child: ActivityRail(
                          onExpand: () => setState(() => _panelExpanded = true),
                        ),
                      ),
                    Expanded(child: _buildWorkspace()),
                    if (_rightPanelExpanded)
                      SizedBox(
                        width: filesPanelWidth,
                        child: FilesPanel(
                          filterController: _filterController,
                          onCollapse: () =>
                              setState(() => _rightPanelExpanded = false),
                        ),
                      )
                    else
                      SizedBox(
                        width: railWidth,
                        child: FilesRail(
                          onExpand: () =>
                              setState(() => _rightPanelExpanded = true),
                        ),
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

  Widget _buildWorkspace() {
    return Column(
      children: [
        WorkspaceTopBar(onOpenSettings: _openSettings),
        BlocBuilder<WorkspaceCubit, WorkspaceState>(
          builder: (context, state) {
            final message = state is WorkspaceReady
                ? _errorMessage(state)
                : null;
            if (message == null) return const SizedBox.shrink();
            return ErrorBanner(message: message);
          },
        ),
        Expanded(child: _buildCenter()),
        BlocBuilder<ChatCubit, ChatState>(
          builder: (context, chatState) {
            final idle = chatState as ChatIdle;
            return BlocBuilder<WorkspaceCubit, WorkspaceState>(
              builder: (context, workspaceState) {
                final ready = _isReadyToSend(workspaceState);
                return Composer(
                  controller: _promptController,
                  focusNode: _promptFocus,
                  suggestions: _suggestions,
                  pendingAttachments: idle.pendingAttachments,
                  sending: idle.sending,
                  ready: ready,
                  onSuggestion: _insertSuggestion,
                  onMention: _startMention,
                  onAttach: _attachFiles,
                  onRemoveAttachment: _chatCubit.removeAttachment,
                  onSend: _send,
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCenter() {
    return BlocBuilder<FileExplorerCubit, FileExplorerState>(
      builder: (context, fileExplorerState) {
        final loaded = fileExplorerState as FileExplorerLoaded;
        final preview = loaded.preview;
        if (preview != null) {
          return PreviewPane(
            preview: preview,
            onMention: _mentionPreviewed,
            onClose: _fileExplorerCubit.closePreview,
          );
        }
        final previewError = loaded.previewError;
        if (previewError != null) {
          return PreviewErrorPane(
            message: previewError,
            onClose: _fileExplorerCubit.closePreview,
          );
        }
        return BlocBuilder<ChatCubit, ChatState>(
          builder: (context, chatState) {
            final idle = chatState as ChatIdle;
            if (idle.messages.isEmpty) {
              return BlocBuilder<WorkspaceCubit, WorkspaceState>(
                builder: (context, workspaceState) {
                  return EmptyState(
                    ready: _isReadyToSend(workspaceState),
                    rootPath: workspaceState is WorkspaceReady
                        ? workspaceState.root?.path
                        : null,
                    onPrompt: (text) {
                      _promptController.text = text;
                      _promptController.selection = TextSelection.collapsed(
                        offset: text.length,
                      );
                      _promptFocus.requestFocus();
                    },
                  );
                },
              );
            }
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 18),
              itemCount: idle.messages.length + (idle.sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == idle.messages.length) {
                  return const ThinkingCard();
                }
                return MessageCard(entry: idle.messages[index]);
              },
            );
          },
        );
      },
    );
  }

  bool _isReadyToSend(WorkspaceState state) =>
      state is WorkspaceReady &&
      !state.connecting &&
      state.selectedModel != null &&
      state.modelState != WorkspaceModelState.starting;

  String? _errorMessage(WorkspaceReady state) {
    final error = state.error;
    if (error == null) return null;
    if (error is AppException) return error.message;
    return error.toString();
  }
}
