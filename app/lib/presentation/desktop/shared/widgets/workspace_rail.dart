import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/chat/view_model/chat_state.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';

/// Secao ativa da area central do shell: Chat ou Git.
enum WorkspaceSection { chat, git }

/// Rail permanente de 50 px com navegacao Chat/Git e abertura da atividade.
class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({
    super.key,
    required this.activeSection,
    required this.onSelectSection,
    required this.onExpandActivity,
  });

  final WorkspaceSection activeSection;
  final ValueChanged<WorkspaceSection> onSelectSection;
  final VoidCallback onExpandActivity;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('workspace-rail'),
      decoration: const BoxDecoration(color: deepNavy),
      child: BlocBuilder<WorkspaceCubit, WorkspaceState>(
        builder: (context, workspaceState) {
          final sessions = workspaceState is WorkspaceReady
              ? workspaceState.sessions
              : const <PersistedSessionSummaryEntity>[];
          return BlocBuilder<ChatCubit, ChatState>(
            builder: (context, chatState) {
              final idle = chatState as ChatIdle;
              final hasCurrent = idle.currentSessionSummary != null;
              final badge = sessions.isNotEmpty || hasCurrent
                  ? '${sessions.length + (hasCurrent ? 1 : 0)}'
                  : null;
              return Column(
                children: [
                  const SizedBox(height: 10),
                  _RailNavIcon(
                    key: const Key('chat-navigation-button'),
                    icon: Icons.chat_bubble_outline_rounded,
                    tooltip: 'Chat',
                    selected: activeSection == WorkspaceSection.chat,
                    onTap: () => onSelectSection(WorkspaceSection.chat),
                  ),
                  _RailNavIcon(
                    key: const Key('git-navigation-button'),
                    icon: Icons.account_tree_outlined,
                    tooltip: 'Git',
                    selected: activeSection == WorkspaceSection.git,
                    onTap: () => onSelectSection(WorkspaceSection.git),
                  ),
                  const Spacer(),
                  _RailNavIcon(
                    key: const Key('rail-sessions-button'),
                    icon: Icons.menu,
                    tooltip: 'Atividade',
                    selected: false,
                    badge: badge,
                    onTap: onExpandActivity,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RailNavIcon extends StatelessWidget {
  const _RailNavIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: selected ? coral : Colors.white60, size: 19),
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
                        color: coral,
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
        ),
      ),
    );
  }
}
