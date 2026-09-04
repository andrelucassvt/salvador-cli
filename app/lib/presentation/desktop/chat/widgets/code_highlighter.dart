import 'package:flutter/material.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';

const keywordStyle = TextStyle(color: ocean, fontWeight: FontWeight.w700);
const commentStyle = TextStyle(color: Color(0xFF7BA05B));
const stringStyle = TextStyle(color: Color(0xFFB4632F));
const numberStyle = TextStyle(color: Color(0xFF8A6BB8));

const _keywordsByLanguage = <String, Set<String>>{
  'dart': {
    'async',
    'await',
    'class',
    'const',
    'else',
    'extends',
    'final',
    'for',
    'if',
    'import',
    'new',
    'return',
    'var',
    'void',
    'while',
  },
  'yaml': {'false', 'null', 'true'},
  'json': {'false', 'null', 'true'},
  'shell': {
    'do',
    'done',
    'echo',
    'elif',
    'else',
    'export',
    'fi',
    'for',
    'if',
    'then',
  },
  'python': {
    'None',
    'True',
    'False',
    'class',
    'def',
    'elif',
    'else',
    'for',
    'if',
    'import',
    'in',
    'return',
    'while',
  },
  'javascript': {
    'async',
    'await',
    'class',
    'const',
    'else',
    'export',
    'for',
    'function',
    'if',
    'import',
    'let',
    'new',
    'return',
    'var',
    'while',
  },
  'typescript': {
    'async',
    'await',
    'class',
    'const',
    'else',
    'export',
    'for',
    'function',
    'if',
    'import',
    'interface',
    'let',
    'new',
    'return',
    'type',
    'var',
    'while',
  },
  'c': {
    'const',
    'else',
    'for',
    'if',
    'int',
    'return',
    'struct',
    'void',
    'while',
  },
  'cpp': {
    'class',
    'const',
    'else',
    'for',
    'if',
    'int',
    'return',
    'struct',
    'template',
    'void',
    'while',
  },
  'java': {
    'class',
    'else',
    'extends',
    'final',
    'for',
    'if',
    'import',
    'int',
    'new',
    'private',
    'public',
    'return',
    'static',
    'void',
    'while',
  },
  'kotlin': {
    'class',
    'else',
    'for',
    'fun',
    'if',
    'import',
    'return',
    'val',
    'var',
    'when',
    'while',
  },
  'go': {
    'break',
    'case',
    'const',
    'else',
    'for',
    'func',
    'go',
    'if',
    'import',
    'package',
    'return',
    'struct',
    'type',
    'var',
  },
  'rust': {
    'as',
    'else',
    'enum',
    'fn',
    'for',
    'if',
    'impl',
    'in',
    'let',
    'loop',
    'match',
    'mod',
    'move',
    'mut',
    'pub',
    'return',
    'struct',
    'use',
    'while',
  },
  'swift': {
    'class',
    'else',
    'enum',
    'extension',
    'for',
    'func',
    'if',
    'import',
    'in',
    'let',
    'return',
    'struct',
    'var',
    'while',
  },
};

List<TextSpan> highlightLine(String line, String language) {
  final keywords = _keywordsByLanguage[language];
  if (keywords == null || line.isEmpty) {
    return [TextSpan(text: line)];
  }
  final spans = <TextSpan>[];
  final pattern = RegExp(
    r'''("[^"]*"|'[^']*'|//[^\n]*|#[^\n]*|\b\d+(?:\.\d+)?\b|[A-Za-z_][A-Za-z0-9_]*)''',
  );
  var last = 0;
  for (final match in pattern.allMatches(line)) {
    if (match.start > last) {
      spans.add(TextSpan(text: line.substring(last, match.start)));
    }
    final token = match.group(0)!;
    final TextStyle? style;
    if (token.startsWith('//') || token.startsWith('#')) {
      style = commentStyle;
    } else if (token.startsWith('"') || token.startsWith("'")) {
      style = stringStyle;
    } else if (RegExp(r'^\d').hasMatch(token)) {
      style = numberStyle;
    } else if (keywords.contains(token)) {
      style = keywordStyle;
    } else {
      style = null;
    }
    spans.add(TextSpan(text: token, style: style));
    last = match.end;
  }
  if (last < line.length) {
    spans.add(TextSpan(text: line.substring(last)));
  }
  return spans;
}
