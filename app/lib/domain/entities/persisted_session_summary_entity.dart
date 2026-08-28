import 'package:flutter/foundation.dart';

@immutable
class PersistedSessionSummaryEntity {
  const PersistedSessionSummaryEntity({
    required this.title,
    required this.startedAt,
    required this.actionCount,
  });

  final String title;
  final DateTime startedAt;
  final int actionCount;

  PersistedSessionSummaryEntity copyWith({
    String? title,
    DateTime? startedAt,
    int? actionCount,
  }) {
    return PersistedSessionSummaryEntity(
      title: title ?? this.title,
      startedAt: startedAt ?? this.startedAt,
      actionCount: actionCount ?? this.actionCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistedSessionSummaryEntity &&
          title == other.title &&
          startedAt == other.startedAt &&
          actionCount == other.actionCount;

  @override
  int get hashCode => Object.hash(title, startedAt, actionCount);

  @override
  String toString() =>
      'PersistedSessionSummaryEntity(title: $title, startedAt: $startedAt, '
      'actionCount: $actionCount)';
}
