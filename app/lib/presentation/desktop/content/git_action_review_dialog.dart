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
                color: _impactCategory(proposal) == _GitImpact.network
                    ? const Color(0xFFEAF4F6)
                    : const Color(0xFFFFEFE9),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _impactIcon(proposal),
                    size: 15,
                    color: _impactCategory(proposal) == _GitImpact.network
                        ? ocean
                        : coral,
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

  static const _networkTypes = <GitActionType>{
    GitActionType.fetch,
    GitActionType.pull,
    GitActionType.push,
    GitActionType.pushForce,
  };

  static _GitImpact _impactCategory(GitActionProposal proposal) {
    if (proposal.risk == GitActionRisk.normal) return _GitImpact.local;
    return _networkTypes.contains(proposal.type)
        ? _GitImpact.network
        : _GitImpact.destructive;
  }

  static IconData _impactIcon(GitActionProposal proposal) =>
      switch (_impactCategory(proposal)) {
        _GitImpact.local => Icons.bolt_outlined,
        _GitImpact.network => Icons.cloud_outlined,
        _GitImpact.destructive => Icons.warning_amber_rounded,
      };

  static String _impact(GitActionProposal proposal) =>
      switch (_impactCategory(proposal)) {
        _GitImpact.local =>
          'Operacao local: executa no repositorio vinculado sem acessar a rede.',
        _GitImpact.network =>
          'Requer acesso a rede para comunicar com os remotos do repositorio.',
        _GitImpact.destructive =>
          'Operacao destrutiva: pode descartar, sobrescrever ou remover dados Git locais.',
      };
}

enum _GitImpact { local, network, destructive }

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
