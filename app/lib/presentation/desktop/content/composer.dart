import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
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
      color: shell,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            children: [
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    color: paper,
                    border: Border.all(color: line),
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
                                    color: ocean,
                                    size: 17,
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      path,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: ink,
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
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: paper,
                  border: Border.all(color: ready ? line : coral),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12082C40),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 62,
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            if (sending || !ready) {
                              return KeyEventResult.handled;
                            }
                            onSend();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          key: const Key('composer-field'),
                          controller: controller,
                          focusNode: focusNode,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          enabled: !sending,
                          style: const TextStyle(
                            color: ink,
                            fontSize: 14,
                            height: 1.45,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: ready
                                ? 'Peça uma alteração ou mencione um arquivo com @…'
                                : 'Conecte ao Ollama e inicie o modelo para começar…',
                            hintStyle: const TextStyle(color: muted),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: sending ? null : onMention,
                          icon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 17,
                          ),
                          label: const Text('Arquivo'),
                        ),
                        const Text(
                          'Enter para enviar · Shift+Enter para quebrar linha',
                          style: TextStyle(color: muted, fontSize: 10),
                        ),
                        FilledButton(
                          key: const Key('send-button'),
                          onPressed: sending || !ready ? null : onSend,
                          style: FilledButton.styleFrom(
                            backgroundColor: ocean,
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
