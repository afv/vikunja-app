import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/presentation/widgets/calendar/calendar_days.dart';

void main() {
  // Monday 12 October 2026 .. Sunday 18 October 2026
  DateTime d(int day) => DateTime(2026, 10, day, 15, 30);

  test('the first three days of the week open on the Monday', () {
    for (final day in [12, 13, 14]) {
      expect(weekStartFor(d(day)), DateTime(2026, 10, 12));
    }
  });

  test('later days open one day before, so the day looked at is visible', () {
    expect(weekStartFor(d(15)), DateTime(2026, 10, 14)); // Thursday
    expect(weekStartFor(d(16)), DateTime(2026, 10, 15)); // Friday
    expect(weekStartFor(d(17)), DateTime(2026, 10, 16)); // Saturday
    expect(weekStartFor(d(18)), DateTime(2026, 10, 17)); // Sunday
  });

  test('the focused day is always among the three visible columns', () {
    for (var day = 12; day <= 25; day++) {
      final start = weekStartFor(d(day));
      final offset = DateTime(2026, 10, day).difference(start).inDays;
      expect(offset, inInclusiveRange(0, 2));
    }
  });
}
