import 'package:flutter/foundation.dart';

@immutable
class AttachedFileEntity {
  const AttachedFileEntity({required this.path, required this.name});

  final String path;
  final String name;

  AttachedFileEntity copyWith({String? path, String? name}) {
    return AttachedFileEntity(
      path: path ?? this.path,
      name: name ?? this.name,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachedFileEntity && path == other.path && name == other.name;

  @override
  int get hashCode => Object.hash(path, name);

  @override
  String toString() => 'AttachedFileEntity(path: $path, name: $name)';
}
