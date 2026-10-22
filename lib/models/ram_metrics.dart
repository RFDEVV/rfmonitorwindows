class RamMetrics {
  RamMetrics._();

  static double? freeMb(Map? ram) {
    if (ram == null) return null;
    final reportedFree = _number(ram['freeMB']);
    if (reportedFree != null) return reportedFree;

    final totalGb = _number(ram['totalGB']);
    final total =
        _number(ram['totalMB']) ?? (totalGb == null ? null : totalGb * 1024);
    if (total == null) return null;

    final usedGb = _number(ram['usedGB']);
    final used =
        _number(ram['usedMB']) ?? (usedGb == null ? null : usedGb * 1024);
    if (used != null) return (total - used).clamp(0.0, total).toDouble();

    final percent = _number(ram['usedPercent']);
    if (percent != null) {
      return (total * (1 - percent.clamp(0, 100) / 100))
          .clamp(0.0, total)
          .toDouble();
    }
    return null;
  }

  static double? totalMb(Map? ram) {
    if (ram == null) return null;
    final totalGb = _number(ram['totalGB']);
    return _number(ram['totalMB']) ?? (totalGb == null ? null : totalGb * 1024);
  }

  static String freeLabel(Map? ram) {
    final free = freeMb(ram);
    return free == null ? '-- MB' : '${free.round()} MB';
  }

  static double? _number(dynamic value) => (value as num?)?.toDouble();
}
