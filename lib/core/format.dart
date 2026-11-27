/// 时长格式化：`mm:ss` 或 `h:mm:ss`。
String formatDuration(Duration? d) {
  if (d == null || d.inMilliseconds <= 0) return '--:--';
  final int totalSeconds = d.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// 大数字缩写：12345 -> 1.2万。
String formatCount(int? n) {
  if (n == null || n <= 0) return '';
  if (n < 10000) return '$n';
  final double v = n / 10000;
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}万';
}

/// 去掉文件名中的非法字符，避免下载时写入失败。
String sanitizeFileName(String input, {int maxLength = 90}) {
  String name = input
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (name.isEmpty) name = 'untitled';
  if (name.length > maxLength) name = name.substring(0, maxLength);
  return name;
}
