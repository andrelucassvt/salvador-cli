import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/git/content/git_action_review_dialog.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_assistant_state.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_assistant_drawer.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_branches_panel.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_commit_graph.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_commit_inspector.dart';
import 'package:salvador_desktop/presentation/desktop/git/widgets/git_worktree_panel.dart';

/// Workspace Git completo: cabecalho com resumo, navegador de refs, grafo de
/// commits, inspector e alteracoes locais. Em larguras compactas, branches
/// viram painel recolhivel e o inspector abre como drawer inferior.
class GitWorkspace extends StatefulWidget {
  const GitWorkspace({super.key, this.onOpenFile});

  final Future<void> Function(String path)? onOpenFile;

  @override
  State<GitWorkspace> createState() => _GitWorkspaceState();
}

class _GitWorkspaceState extends State<GitWorkspace> {
  bool _branchesVisible = false;
  bool _inspectorVisible = false;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GitCubit>();
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        final Widget content = switch (state) {
          GitEmpty() => const _GitHint(
            icon: Icons.account_tree_outlined,
            title: 'Git',
            message: 'Selecione um projeto para ver o status Git.',
          ),
          GitLoading(previous: null) => const _GitLoadingView(),
          GitLoading(previous: final previous?) => _LoadedWorkspace(
            state: previous,
            refreshing: true,
            onRefresh: cubit.refresh,
            branchesVisible: _branchesVisible,
            inspectorVisible: _inspectorVisible,
            onToggleBranches: () =>
                setState(() => _branchesVisible = !_branchesVisible),
            onToggleInspector: () =>
                setState(() => _inspectorVisible = !_inspectorVisible),
            onOpenFile: widget.onOpenFile,
          ),
          GitLoaded() => _LoadedWorkspace(
            state: state,
            refreshing: false,
            onRefresh: cubit.refresh,
            branchesVisible: _branchesVisible,
            inspectorVisible: _inspectorVisible,
            onToggleBranches: () =>
                setState(() => _branchesVisible = !_branchesVisible),
            onToggleInspector: () =>
                setState(() => _inspectorVisible = !_inspectorVisible),
            onOpenFile: widget.onOpenFile,
          ),
          GitNotRepository() => _GitHint(
            icon: Icons.folder_off_outlined,
            title: 'Sem repositório',
            message: 'Esta pasta não é um repositório Git.',
            action: cubit.refresh,
          ),
          GitRepositoryOutsideRoot(topLevel: final topLevel) => _GitHint(
            icon: Icons.folder_open_outlined,
            title: 'Repositório fora da raiz',
            message: topLevel == null
                ? 'O repositório Git está acima desta pasta. Abra o diretório real do repositório como raiz.'
                : 'O repositório Git está em "$topLevel". Abra essa pasta como raiz para ver o status Git.',
            action: cubit.refresh,
          ),
          GitFailure(message: final message) => _GitHint(
            icon: Icons.error_outline_rounded,
            title: 'Falha ao acessar o Git',
            message: message,
            action: cubit.refresh,
          ),
        };
        return Container(
          key: const Key('git-workspace'),
          color: gitWorkspaceSurface,
          constraints: const BoxConstraints.expand(),
          child: Stack(
            children: [
              Positioned.fill(child: content),
              BlocBuilder<GitAssistantCubit, GitAssistantState>(
                builder: (context, assistantState) {
                  final open = (assistantState as GitAssistantIdle).drawerOpen;
                  if (!open) return const SizedBox.shrink();
                  return const Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: GitAssistantDrawer(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoadedWorkspace extends StatelessWidget {
  const _LoadedWorkspace({
    required this.state,
    required this.refreshing,
    required this.onRefresh,
    required this.branchesVisible,
    required this.inspectorVisible,
    required this.onToggleBranches,
    required this.onToggleInspector,
    this.onOpenFile,
  });

  final GitLoaded state;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final bool branchesVisible;
  final bool inspectorVisible;
  final VoidCallback onToggleBranches;
  final VoidCallback onToggleInspector;
  final Future<void> Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        return Column(
          children: [
            if (refreshing) const LinearProgressIndicator(minHeight: 2),
            _GitHeader(
              snapshot: state.snapshot,
              executing: state.executingAction != null,
              onRefresh: onRefresh,
            ),
            if (state.actionError != null)
              _ActionErrorBanner(message: state.actionError!),
            Expanded(
              child: compact
                  ? _CompactLayout(
                      state: state,
                      branchesVisible: branchesVisible,
                      inspectorVisible: inspectorVisible,
                      onToggleBranches: onToggleBranches,
                      onToggleInspector: onToggleInspector,
                      onOpenFile: onOpenFile,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: const [
                              GitBranchesPanel(),
                              Expanded(child: GitCommitGraph()),
                              GitCommitInspector(),
                            ],
                          ),
                        ),
                        GitWorktreePanel(onOpenFile: onOpenFile),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.state,
    required this.branchesVisible,
    required this.inspectorVisible,
    required this.onToggleBranches,
    required this.onToggleInspector,
    this.onOpenFile,
  });

  final GitLoaded state;
  final bool branchesVisible;
  final bool inspectorVisible;
  final VoidCallback onToggleBranches;
  final VoidCallback onToggleInspector;
  final Future<void> Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final showInspector =
        inspectorVisible && state.selectedFilePath != null ||
        (inspectorVisible &&
            (state.selectedCommit != null || state.visibleCommits.isNotEmpty));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              IconButton(
                key: const Key('git-toggle-branches'),
                tooltip: branchesVisible
                    ? 'Ocultar branches'
                    : 'Mostrar branches',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleBranches,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
              ),
              const Spacer(),
              IconButton(
                key: const Key('git-toggle-inspector'),
                tooltip: inspectorVisible
                    ? 'Fechar inspector'
                    : 'Abrir inspector',
                visualDensity: VisualDensity.compact,
                onPressed: onToggleInspector,
                icon: const Icon(Icons.info_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: branchesVisible
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    GitBranchesPanel(),
                    Expanded(child: GitCommitGraph()),
                  ],
                )
              : const GitCommitGraph(),
        ),
        if (showInspector)
          SizedBox(
            height: 260,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [Expanded(child: GitCommitInspector())],
            ),
          )
        else
          GitWorktreePanel(onOpenFile: onOpenFile),
      ],
    );
  }
}

class _GitHeader extends StatelessWidget {
  const _GitHeader({
    required this.snapshot,
    required this.executing,
    required this.onRefresh,
  });

  final GitSnapshot snapshot;
  final bool executing;
  final Future<void> Function() onRefresh;

  Future<void> _requestFetch(BuildContext context) async {
    const proposal = GitActionProposal(type: GitActionType.fetch);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GitActionReviewDialog(proposal: proposal),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<GitCubit>().executeApproved(proposal);
  }

  @override
  Widget build(BuildContext context) {
    final repository = snapshot.repository;
    final branch = repository.branch ?? 'HEAD desanexado';
    final switchableBranches = snapshot.localBranches
        .where((ref) => ref.shortName != repository.branch)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      decoration: const BoxDecoration(
        color: gitToolbarSurface,
        border: Border(bottom: BorderSide(color: line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final showMetrics = constraints.maxWidth >= 840;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (!compact)
                      Container(
                        key: const Key('git-status-chip'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: snapshot.clean
                              ? gitSubtleSurface
                              : const Color(0xFFFFEFE9),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          snapshot.clean ? 'limpo' : 'sujo',
                          style: TextStyle(
                            color: snapshot.clean
                                ? const Color(0xFF2E7D57)
                                : coral,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    if (!compact) const SizedBox(width: 12),
                    Flexible(
                      child: switchableBranches.isEmpty
                          ? _BranchName(branch: branch)
                          : PopupMenuButton<GitRef>(
                              key: const Key('git-branch-selector'),
                              tooltip: 'Trocar branch',
                              padding: EdgeInsets.zero,
                              onSelected: (ref) => context
                                  .read<GitCubit>()
                                  .checkoutBranch(ref.shortName),
                              itemBuilder: (context) => [
                                for (final ref in switchableBranches)
                                  PopupMenuItem(
                                    key: Key('git-checkout-${ref.name}'),
                                    value: ref,
                                    child: Text(
                                      ref.shortName,
                                      style: const TextStyle(
                                        fontFamily: 'JetBrains Mono',
                                      ),
                                    ),
                                  ),
                              ],
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(child: _BranchName(branch: branch)),
                                  const Icon(
                                    Icons.arrow_drop_down_rounded,
                                    color: muted,
                                  ),
                                ],
                              ),
                            ),
                    ),
                    if (showMetrics) ...[
                      const SizedBox(width: 10),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'HEAD ${_short(repository.headOid)}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 10.5,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            if (snapshot.upstream != null) ...[
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.call_split_rounded,
                                size: 12,
                                color: muted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                snapshot.upstream!,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 10.5,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                            ],
                            const SizedBox(width: 10),
                            Text(
                              'ahead',
                              style: const TextStyle(
                                color: Color(0xFF2E7D57),
                                fontSize: 10.5,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            Text(
                              '${snapshot.ahead}',
                              style: const TextStyle(
                                color: Color(0xFF2E7D57),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'behind',
                              style: const TextStyle(
                                color: Color(0xFFB3492E),
                                fontSize: 10.5,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                            Text(
                              '${snapshot.behind}',
                              style: const TextStyle(
                                color: Color(0xFFB3492E),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(),
              Tooltip(
                message: 'Buscar alterações remotas',
                child: compact
                    ? IconButton(
                        key: const Key('git-fetch-button'),
                        visualDensity: VisualDensity.compact,
                        onPressed: executing
                            ? null
                            : () => _requestFetch(context),
                        icon: executing
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_download_outlined,
                                size: 18,
                              ),
                      )
                    : OutlinedButton.icon(
                        key: const Key('git-fetch-button'),
                        onPressed: executing
                            ? null
                            : () => _requestFetch(context),
                        icon: executing
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.cloud_download_outlined,
                                size: 16,
                              ),
                        label: const Text('Fetch'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: 'Pedir ao Salvador',
                child: FilledButton.icon(
                  key: const Key('git-ask-assistant-button'),
                  onPressed: () =>
                      context.read<GitAssistantCubit>().openDrawer(),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                  label: compact
                      ? const SizedBox.shrink()
                      : const Text('Pedir ao Salvador'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ocean,
                    foregroundColor: paper,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('git-refresh-button'),
                tooltip: 'Atualizar',
                visualDensity: VisualDensity.compact,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _short(String? oid) =>
      oid == null ? 'n/d' : oid.substring(0, 7);
}

class _BranchName extends StatelessWidget {
  const _BranchName({required this.branch});

  final String branch;

  @override
  Widget build(BuildContext context) {
    return Text(
      branch,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
        fontFamily: 'JetBrains Mono',
      ),
    );
  }
}

class _ActionErrorBanner extends StatelessWidget {
  const _ActionErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('git-action-error-banner'),
      color: const Color(0xFFFFEFE9),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 15, color: coral),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Falha na ação: $message',
              style: const TextStyle(color: Color(0xFF7A3B2E), fontSize: 11.5),
            ),
          ),
          IconButton(
            tooltip: 'Descartar erro',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.read<GitCubit>().clearActionError(),
            icon: const Icon(Icons.close_rounded, size: 15, color: coral),
          ),
        ],
      ),
    );
  }
}

class _GitLoadingView extends StatelessWidget {
  const _GitLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: ocean),
          ),
          SizedBox(height: 14),
          Text(
            'Carregando repositório...',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _GitHint extends StatelessWidget {
  const _GitHint({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: line),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 12.5, height: 1.5),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('git-refresh-button'),
                onPressed: action,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
