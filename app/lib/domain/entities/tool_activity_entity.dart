import 'package:flutter/foundation.dart';
import 'package:salvador_cli/salvador_cli.dart';

@immutable
class ToolActivityEntity {
  ToolActivityEntity({required this.call, required this.result, DateTime? happenedAt})
    : happenedAt = happenedAt ?? DateTime.now();

  final ToolCall call;
  final String result;
  final DateTime happenedAt;

  String get summary {
    final path = call.arguments['path'];
    if (path is String) return path;
    final command = call.arguments['command'];
    if (command is String) return command;
    return call.arguments.keys.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolActivityEntity &&
          call == other.call &&
          result == other.result &&
          happenedAt == other.happenedAt;

  @override
  int get hashCode => Object.hash(call, result, happenedAt);

  @override
  String toString() =>
      'ToolActivityEntity(call: ${call.name}, result: $result, happenedAt: $happenedAt)';
}
