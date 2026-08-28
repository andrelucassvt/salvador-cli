String formatBytes(int bytes) {
  if (bytes <= 0) return 'n/d';
  final gb = bytes / 1024 / 1024 / 1024;
  if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}

String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return '${diff.inMinutes} min';
  if (diff.inDays < 1) return '${diff.inHours} h';
  return '${diff.inDays} d';
}

String formatSessionDate(DateTime date) {
  final now = DateTime.now();
  final sameDay =
      date.year == now.year && date.month == now.month && date.day == now.day;
  if (sameDay) {
    return 'hoje ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
