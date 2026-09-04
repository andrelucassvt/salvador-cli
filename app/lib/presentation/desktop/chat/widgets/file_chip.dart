import 'package:flutter/material.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';

/// Reusado em: `mentionedFiles`/`attachedFiles` no histórico de mensagens
/// (`MessageCard`) e na lista de anexos pendentes do `Composer`.
class FileChip extends StatelessWidget {
  const FileChip({
    super.key,
    required this.label,
    this.showAtPrefix = true,
    this.onRemove,
  });

  final String label;
  final bool showAtPrefix;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F2F3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            showAtPrefix ? '@$label' : label,
            style: const TextStyle(
              color: ocean,
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: const Icon(Icons.close_rounded, size: 12, color: ocean),
            ),
          ],
        ],
      ),
    );
  }
}
