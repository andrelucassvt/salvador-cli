import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/domain/entities/chat_message_entity.dart';
import 'package:salvador_desktop/domain/entities/tool_activity_entity.dart';
import 'package:salvador_desktop/presentation/desktop/content/git_action_review_dialog.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_assistant_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';

/// Conversa contextual do assistente Git: mensagens independentes do chat
/// principal, chips da selecao atual, atividades, propostas pendentes e
/// composer com o mesmo fluxo seguro de iniciar o modelo antes de enviar.
class GitAssistantDrawer extends StatefulWidget {
  const GitAssistantDrawer({super.key});

  @override
  State<GitAssistantDrawer> createState() => _GitAssistantDrawerState();
}

class _GitAssistantDrawerState extends State<GitAssistantDrawer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final workspaceCubit = context.read<WorkspaceCubit>();
    final assistant = context.read<GitAssistantCubit>();
    final gitCubit = context.read<GitCubit>();
    final workspace = workspaceCubit.state;
    if (workspace is WorkspaceReady &&
        workspace.modelState == WorkspaceModelState.stopped &&
        workspace.selectedModel != null &&
        !workspace.connecting) {
      await workspaceCubit.startModel();
      final after = workspaceCubit.state;
      if (after is! WorkspaceReady ||
          after.modelState != WorkspaceModelState.running) {
        return;
      }
      assistant.updateReadiness(true);
    }
    final gitState = gitCubit.state;
    if (gitState is GitLoaded) {
      assistant.setContext(
        serializeGitContext(
          gitState.snapshot,
          selectedRef: gitState.selectedRef,
          selectedCommitHash: gitState.selectedCommitHash,
          selectedFilePath: gitState.selectedFilePath,
        ),
      );
    } else {
      assistant.setContext(null);
    }
    _controller.clear();
    await assistant.send(text);
  }

  void _reviewProposal(int index, GitActionProposal proposal) async {
    final assistant = context.read<GitAssistantCubit>();
    final gitCubit = context.read<GitCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GitActionReviewDialog(proposal: proposal),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    final executed = await gitCubit.executeApproved(proposal);
    if (executed) assistant.dismissProposal(proposal);
  }

  @override
  Widget build(BuildContext context) {
    final assistant = context.read<GitAssistantCubit>();
    return BlocBuilder<GitAssistantCubit, GitAssistantState>(
      builder: (context, state) {
        final idle = state as GitAssistantIdle;
        return BlocBuilder<GitCubit, GitState>(
          builder: (context, gitState) {
            return Container(
              key: const Key('git-assistant-drawer'),
              width: 344,
              decoration: const BoxDecoration(
                color: deepNavy,
                border: Border(left: BorderSide(color: Color(0x1AFFFFFF))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                    child: Row(
                      children: [
                        const Text(
                          'ASSISTENTE GIT',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          key: const Key('git-assistant-close'),
                          tooltip: 'Fechar assistente',
                          visualDensity: VisualDensity.compact,
                          onPressed: assistant.closeDrawer,
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (gitState is GitLoaded) _SelectionChips(git: gitState),
                  Expanded(
                    child: idle.messages.isEmpty
                        ? const _EmptyConversation()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            itemCount: idle.messages.length,
                            itemBuilder: (context, index) =>
                                _MessageBubble(message: idle.messages[index]),
                          ),
                  ),
                  if (idle.activities.isNotEmpty)
                    _ActivitiesStrip(activities: idle.activities),
                  if (idle.pendingProposals.isNotEmpty)
                    _PendingProposals(
                      proposals: idle.pendingProposals,
                      onReview: _reviewProposal,
                      onCancel: assistant.dismissProposal,
                    ),
                  if (idle.errorKind == GitAssistantErrorKind.sendFailed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: Text(
                        idle.error is AppException
                            ? (idle.error! as AppException).message
                            : 'Falha ao enviar a mensagem.',
                        style: const TextStyle(
                          color: Color(0xFFFFB4A3),
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed) {
                                if (idle.sending) {
                                  return KeyEventResult.handled;
                                }
                                _send();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              key: const Key('git-assistant-field'),
                              controller: _controller,
                              minLines: 1,
                              maxLines: 5,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                              decoration: InputDecoration(
                                hintText: idle.sending
                                    ? 'Aguardando resposta…'
                                    : 'Pergunte sobre o repositório…',
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                ),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: .07),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                enabled: !idle.sending,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const Key('git-assistant-send'),
                          tooltip: 'Enviar',
                          onPressed: idle.sending ? null : _send,
                          icon: idle.sending
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 17,
                                ),
                        ),
                      ],
                    ),
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

class _SelectionChips extends StatelessWidget {
  const _SelectionChips({required this.git});

  final GitLoaded git;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    final branch = git.snapshot.repository.branch;
    if (branch != null) {
      chips.add(_Chip(icon: Icons.account_tree_outlined, label: branch));
    }
    final commit = git.selectedCommit;
    if (commit != null) {
      chips.add(_Chip(icon: Icons.commit_rounded, label: commit.shortHash));
    }
    final file = git.selectedFilePath;
    if (file != null) {
      chips.add(_Chip(icon: Icons.description_outlined, label: file));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Wrap(
        key: const Key('git-assistant-chips'),
        spacing: 6,
        runSpacing: 6,
        children: chips,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: coral),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 270),
        decoration: BoxDecoration(
          color: isUser ? ocean : Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.white70,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Peça análises e operações Git. Mutações propostas aparecem aqui '
        'para revisão antes de qualquer execução.',
        style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
      ),
    );
  }
}

class _ActivitiesStrip extends StatelessWidget {
  const _ActivitiesStrip({required this.activities});

  final List<ToolActivityEntity> activities;

  @override
  Widget build(BuildContext context) {
    final recent = activities.length > 3
        ? activities.sublist(activities.length - 3)
        : activities;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final activity in recent)
            Text(
              '· ${activity.call.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9.5,
                fontFamily: 'JetBrains Mono',
              ),
            ),
        ],
      ),
    );
  }
}

class _PendingProposals extends StatelessWidget {
  const _PendingProposals({
    required this.proposals,
    required this.onReview,
    required this.onCancel,
  });

  final List<GitActionProposal> proposals;
  final void Function(int index, GitActionProposal proposal) onReview;
  final ValueChanged<GitActionProposal> onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'PROPOSTAS PENDENTES',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < proposals.length; index++)
            Container(
              key: Key('git-proposal-$index'),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEFE9),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    proposals[index].summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7A3B2E),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      FilledButton(
                        key: Key('git-review-proposal-$index'),
                        style: FilledButton.styleFrom(
                          backgroundColor: coral,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => onReview(index, proposals[index]),
                        child: const Text(
                          'Revisar',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        key: Key('git-cancel-proposal-$index'),
                        onPressed: () => onCancel(proposals[index]),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
