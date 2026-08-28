import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/chat_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/folder_menu.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/model_menu.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/start_stop_button.dart';
import 'package:window_manager/window_manager.dart';

class MacTitleBar extends StatelessWidget {
  const MacTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    if (!isMac) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('mac-title-bar'),
      height: titleBarHeight,
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
          color: deepNavy,
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
          decoration: const BoxDecoration(color: coral, shape: BoxShape.circle),
          child: const Icon(Icons.code, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 120) return const SizedBox.shrink();
            return const Text(
              'SALVADOR',
              style: TextStyle(
                color: navy,
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

class WorkspaceTopBar extends StatelessWidget {
  const WorkspaceTopBar({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, workspaceState) {
        if (workspaceState is! WorkspaceReady) return const SizedBox.shrink();
        final workspaceCubit = context.read<WorkspaceCubit>();
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 960;
            final veryCompact = constraints.maxWidth < 780;
            return Container(
              key: const Key('workspace-top-bar'),
              height: topBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                color: paper,
                border: Border(bottom: BorderSide(color: line)),
              ),
              child: Row(
                children: [
                  Row(
                    children: [
                      if (!compact) ...[
                        const _LogoMark(),
                        const SizedBox(width: 10),
                      ],
                      FolderMenu(state: workspaceState, cubit: workspaceCubit),
                    ],
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        // color: Colors.red.withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        spacing: 10,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: line),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ModelMenu(
                              state: workspaceState,
                              cubit: workspaceCubit,
                            ),
                          ),
                          // const SizedBox(width: 8),
                          StartStopButton(
                            state: workspaceState,
                            cubit: workspaceCubit,
                            iconOnly: veryCompact,
                          ),
                        ],
                      ),
                    ),
                  ),

                  BlocBuilder<ChatCubit, ChatState>(
                    builder: (context, chatState) {
                      final chatCubit = context.read<ChatCubit>();
                      final messages = (chatState as ChatIdle).messages;
                      void onNewSession() => chatCubit.newSession(
                        onSessionEnded:
                            (PersistedSessionSummaryEntity summary) =>
                                workspaceCubit.recordSession(summary),
                      );
                      if (veryCompact) {
                        return IconButton(
                          key: const Key('new-session-button'),
                          tooltip: 'Nova sessão',
                          onPressed: messages.isEmpty ? null : onNewSession,
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 18,
                          ),
                        );
                      }
                      return TextButton.icon(
                        key: const Key('new-session-button'),
                        onPressed: messages.isEmpty ? null : onNewSession,
                        icon: const Icon(Icons.add_comment_outlined, size: 17),
                        label: const Text('Nova sessão'),
                      );
                    },
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
      },
    );
  }
}
