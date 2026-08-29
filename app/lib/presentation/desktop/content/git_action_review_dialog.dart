import 'package:flutter/material.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';

/// Revisao explicita de uma [GitActionProposal]: mostra tipo, refs, caminhos,
/// mensagem e impacto antes de qualquer execucao. Nada executa na abertura.
class GitActionReviewDialog extends StatelessWidget {
  const GitActionReviewDialog({super.key, required this.proposal});

  final GitActionProposal proposal;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('git-action-review-dialog'),
      title: const Text('Confirmar ação Git'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(
              label: 'TIPO',
              value: proposal.type.label,
              icon: Icons.build_outlined,
            ),
            if (proposal.refName != null)
              _Field(
                label: 'REF',
                value: proposal.refName!,
                icon: Icons.account_tree_outlined,
              ),
            if (proposal.paths.isNotEmpty)
              _Field(
                label: 'CAMINHOS (${proposal.paths.length})',
                value: proposal.paths.join(', '),
                icon: Icons.description_outlined,
              ),
            if (proposal.message != null)
              _Field(
                label: 'MENSAGEM',
                value: proposal.message!,
                icon: Icons.edit_note_rounded,
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isNetwork(proposal)
                    ? const Color(0xFFEAF4F6)
                    : const Color(0xFFFFEFE9),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _isNetwork(proposal)
                        ? Icons.cloud_outlined
                        : Icons.bolt_outlined,
                    size: 15,
                    color: _isNetwork(proposal) ? ocean : coral,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _impact(proposal),
                      style: const TextStyle(
                        color: ink,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('git-dialog-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('git-dialog-confirm'),
          style: FilledButton.styleFrom(backgroundColor: coral),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }

  static bool _isNetwork(GitActionProposal proposal) =>
      proposal.type == GitActionType.fetch;

  static String _impact(GitActionProposal proposal) => switch (proposal.type) {
    GitActionType.fetch =>
      'Requer acesso a rede: atualiza refs remotas do '
          'repositorio. O worktree nao muda.',
    GitActionType.createBranch ||
    GitActionType.checkoutBranch => 'Altera a branch ativa do worktree local.',
    GitActionType.stage => 'Adiciona os arquivos selecionados ao index.',
    GitActionType.unstage => 'Remove os arquivos selecionados do index.',
    GitActionType.commit =>
      'Cria um commit local com as mudancas '
          'preparadas.',
    GitActionType.merge || GitActionType.rebase =>
      'Integra a branch '
          'informada na branch atual; pode deixar conflitos para resolver.',
  };
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 12,
                    height: 1.4,
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
