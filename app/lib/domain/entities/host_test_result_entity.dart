import 'package:flutter/foundation.dart';

@immutable
class HostTestResultEntity {
  const HostTestResultEntity({
    required this.ok,
    this.latency,
    this.modelCount = 0,
    this.error,
  });

  final bool ok;
  final Duration? latency;
  final int modelCount;
  final String? error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HostTestResultEntity &&
          ok == other.ok &&
          latency == other.latency &&
          modelCount == other.modelCount &&
          error == other.error;

  @override
  int get hashCode => Object.hash(ok, latency, modelCount, error);

  @override
  String toString() =>
      'HostTestResultEntity(ok: $ok, latency: $latency, '
      'modelCount: $modelCount, error: $error)';
}
