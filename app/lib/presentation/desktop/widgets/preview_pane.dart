import 'package:flutter/material.dart';
import 'package:salvador_desktop/common/utils/formatters.dart';
import 'package:salvador_desktop/domain/entities/file_preview_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/code_highlighter.dart';

class PreviewPane extends StatelessWidget {
  const PreviewPane({
    super.key,
    required this.preview,
    required this.onMention,
    required this.onClose,
  });

  final FilePreviewEntity preview;
  final VoidCallback onMention;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final lines = preview.content.split('\n');
    return Column(
      key: const Key('preview-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          decoration: const BoxDecoration(
            color: paper,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F2F3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  preview.language.toUpperCase(),
                  style: const TextStyle(
                    color: ocean,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${preview.lineCount} linhas · ${formatBytes(preview.sizeBytes)}',
                style: const TextStyle(
                  color: muted,
                  fontSize: 10.5,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                key: const Key('mention-preview-button'),
                onPressed: onMention,
                icon: const Icon(Icons.alternate_email_rounded, size: 15),
                label: const Text('Mencionar com @'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ocean,
                  side: const BorderSide(color: line),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('close-preview-button'),
                tooltip: 'Fechar preview',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: lines.length,
            itemBuilder: (context, index) => _PreviewLine(
              number: index + 1,
              text: lines[index],
              language: preview.language,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.number,
    required this.text,
    required this.language,
  });

  final int number;
  final String text;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: line,
                fontSize: 11,
                height: 1.5,
                fontFamily: 'JetBrains Mono',
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              children: highlightLine(text, language),
              style: const TextStyle(
                color: ink,
                fontSize: 12,
                height: 1.5,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PreviewErrorPane extends StatelessWidget {
  const PreviewErrorPane({
    super.key,
    required this.message,
    required this.onClose,
  });

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('preview-error-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
          decoration: const BoxDecoration(
            color: paper,
            border: Border(bottom: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: coral, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Não foi possível abrir o preview',
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('close-preview-button'),
                tooltip: 'Fechar',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            message,
            style: const TextStyle(
              color: ink,
              fontSize: 12.5,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
    );
  }
}
