import 'package:flutter_test/flutter_test.dart';
import 'package:taranaka/core/platform/local_reminders.dart';

void main() {
  test('reminder ids are stable and positive', () {
    final a = LocalReminder(
      key: 'vaccin-c1-dayBefore-2026-02-12',
      at: DateTime(2026, 2, 11, 9),
      title: 't',
      body: 'b',
    );
    final b = LocalReminder(
      key: 'vaccin-c1-dayBefore-2026-02-12',
      at: DateTime(2026, 2, 11, 9),
      title: 'x',
      body: 'y',
    );
    final c = LocalReminder(
      key: 'vaccin-c1-weekBefore-2026-02-12',
      at: DateTime(2026, 2, 5, 9),
      title: 't',
      body: 'b',
    );
    expect(a.id, b.id);
    expect(a.id, isNot(c.id));
    expect(a.id, greaterThanOrEqualTo(0));
    expect(a.id, lessThanOrEqualTo(0x7fffffff));
  });
}
