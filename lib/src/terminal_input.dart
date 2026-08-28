import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'file_mentions.dart';

class TerminalInputInterrupted implements Exception {
  const TerminalInputInterrupted();
}

/// A small, dependency-free line editor. In a terminal it keeps the current
/// buffer visible while an `@file` completion menu is shown below it.
class TerminalInput {
  TerminalInput({
    Stream<List<int>>? input,
    StringSink? output,
    bool? interactive,
  }) : _terminal = input == null ? stdin : null,
       _output = output ?? stdout,
       interactive =
           interactive ??
           (input == null && stdin.hasTerminal && stdout.hasTerminal),
       _chunks = StreamIterator((input ?? stdin).transform(utf8.decoder));

  final Stdin? _terminal;
  final StringSink _output;
  final bool interactive;
  final StreamIterator<String> _chunks;
  final List<String> _characters = [];
  int _characterIndex = 0;
  bool _started = false;
  bool _closed = false;
  bool _skipLineFeed = false;
  bool? _previousEchoMode;
  bool? _previousLineMode;

  Future<String?> readLine({
    required String prompt,
    FileMentionService? mentions,
  }) async {
    if (prompt.contains('\n') || prompt.contains('\r')) {
      throw ArgumentError.value(
        prompt,
        'prompt',
        'nao pode conter quebra de linha',
      );
    }
    mentions?.refresh();
    _start();
    var text = '';
    var cursor = 0;
    var selection = 0;

    void setText(String value) {
      text = value;
    }

    if (interactive) {
      _render(prompt, text, cursor, const [], selection);
    } else {
      _output.write(prompt);
    }

    while (true) {
      final character = await _nextCharacter();
      if (character == null) {
        if (text.isEmpty) return null;
        _finish(prompt, text);
        return text;
      }
      final code = character.runes.single;
      if (_skipLineFeed && code == 10) {
        _skipLineFeed = false;
        continue;
      }
      _skipLineFeed = false;

      final active = mentions?.activeMention(text, cursor);
      var suggestions = active == null
          ? const <String>[]
          : mentions!.suggest(active.query);

      if (code == 3) {
        if (interactive) _finish(prompt, text);
        throw const TerminalInputInterrupted();
      }
      if (code == 4 && text.isEmpty) {
        if (interactive) _finish(prompt, text);
        return null;
      }
      if (code == 13 || code == 10) {
        if (code == 13) _skipLineFeed = true;
        _finish(prompt, text);
        return text;
      }
      if (code == 9 && active != null && suggestions.isNotEmpty) {
        final chosen = suggestions[selection.clamp(0, suggestions.length - 1)];
        final rendered = chosen.contains(' ') ? '@"$chosen" ' : '@$chosen ';
        setText(text.replaceRange(active.start, cursor, rendered));
        cursor = active.start + rendered.length;
        selection = 0;
      } else if (code == 8 || code == 127) {
        if (cursor > 0) {
          final previous = _previousRuneStart(text, cursor);
          setText(text.replaceRange(previous, cursor, ''));
          cursor = previous;
          selection = 0;
        }
      } else if (code == 27) {
        final key = await _readEscapeKey();
        switch (key) {
          case 'left':
            if (cursor > 0) cursor = _previousRuneStart(text, cursor);
          case 'right':
            if (cursor < text.length) cursor = _nextRuneEnd(text, cursor);
          case 'up':
            if (suggestions.isNotEmpty) {
              selection = (selection - 1) % suggestions.length;
            }
          case 'down':
            if (suggestions.isNotEmpty) {
              selection = (selection + 1) % suggestions.length;
            }
          case 'home':
            cursor = 0;
          case 'end':
            cursor = text.length;
          case 'delete':
            if (cursor < text.length) {
              setText(
                text.replaceRange(cursor, _nextRuneEnd(text, cursor), ''),
              );
            }
        }
      } else if (code >= 32) {
        setText(text.replaceRange(cursor, cursor, character));
        cursor += character.length;
        selection = 0;
      }

      final nextActive = mentions?.activeMention(text, cursor);
      suggestions = nextActive == null
          ? const <String>[]
          : mentions!.suggest(nextActive.query);
      if (selection >= suggestions.length) selection = 0;
      if (interactive) {
        _render(prompt, text, cursor, suggestions, selection);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _chunks.cancel();
    } finally {
      _restoreTerminal();
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    if (interactive && _terminal != null) {
      _previousEchoMode = _terminal.echoMode;
      _previousLineMode = _terminal.lineMode;
      _terminal
        ..echoMode = false
        ..lineMode = false;
    }
  }

  Future<String?> _nextCharacter() async {
    while (_characterIndex >= _characters.length) {
      if (!await _chunks.moveNext()) return null;
      _characters
        ..clear()
        ..addAll(_chunks.current.runes.map(String.fromCharCode));
      _characterIndex = 0;
    }
    return _characters[_characterIndex++];
  }

  Future<String?> _readEscapeKey() async {
    final second = await _nextCharacter();
    if (second != '[' && second != 'O') return null;
    final third = await _nextCharacter();
    switch (third) {
      case 'A':
        return 'up';
      case 'B':
        return 'down';
      case 'C':
        return 'right';
      case 'D':
        return 'left';
      case 'H':
        return 'home';
      case 'F':
        return 'end';
      case '3':
        if (await _nextCharacter() == '~') return 'delete';
    }
    return null;
  }

  void _render(
    String prompt,
    String text,
    int cursor,
    List<String> suggestions,
    int selection,
  ) {
    _output.write('\r\x1b[J$prompt$text');
    for (var index = 0; index < suggestions.length; index++) {
      final marker = index == selection ? '›' : ' ';
      _output.write('\n  $marker @${_safeDisplay(suggestions[index])}');
    }
    if (suggestions.isNotEmpty) {
      _output.write('\x1b[${suggestions.length}A');
    }
    _output.write('\r');
    final column = prompt.length + text.substring(0, cursor).runes.length;
    if (column > 0) _output.write('\x1b[${column}C');
  }

  void _finish(String prompt, String text) {
    if (interactive) {
      _output.write('\r\x1b[J$prompt$text\n');
    } else {
      _output.write('\n');
    }
  }

  void _restoreTerminal() {
    final terminal = _terminal;
    if (terminal == null || !interactive) return;
    if (_previousLineMode != null) terminal.lineMode = _previousLineMode!;
    if (_previousEchoMode != null) terminal.echoMode = _previousEchoMode!;
  }

  static int _previousRuneStart(String text, int cursor) {
    var index = cursor - 1;
    if (index > 0 && _isLowSurrogate(text.codeUnitAt(index))) index--;
    return index;
  }

  static int _nextRuneEnd(String text, int cursor) {
    var index = cursor + 1;
    if (index < text.length && _isHighSurrogate(text.codeUnitAt(cursor))) {
      index++;
    }
    return index;
  }

  static bool _isLowSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

  static String _safeDisplay(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '�');
}
