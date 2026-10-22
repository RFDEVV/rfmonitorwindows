import 'package:flutter_test/flutter_test.dart';
import 'package:rfmonitor/models/ram_metrics.dart';

void main() {
  group('RamMetrics.freeMb', () {
    test('uses the reported free memory when available', () {
      expect(RamMetrics.freeMb({'freeMB': 512, 'totalMB': 1024}), 512);
    });

    test('derives free memory from total and used megabytes', () {
      expect(RamMetrics.freeMb({'totalMB': 4096, 'usedMB': 1536}), 2560);
    });

    test('converts gigabytes before subtracting used memory', () {
      expect(RamMetrics.freeMb({'totalGB': 8, 'usedGB': 3}), 5120);
    });

    test('derives free memory from the used percentage', () {
      expect(RamMetrics.freeMb({'totalMB': 2000, 'usedPercent': 25}), 1500);
    });

    test('returns null when the server sends no usable RAM metrics', () {
      expect(RamMetrics.freeMb({'usedPercent': 50}), isNull);
      expect(RamMetrics.freeLabel(null), '-- MB');
    });
  });
}
