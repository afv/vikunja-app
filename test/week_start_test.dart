import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/presentation/widgets/calendar/calendar_days.dart';

void main() {
  test('the week view opens with the focused day in the middle column', () {
    for (var day = 12; day <= 25; day++) {
      final focus = DateTime(2026, 10, day, 15, 30);
      expect(weekStartFor(focus), DateTime(2026, 10, day - 1));
    }
  });

  test('works across month and year ends', () {
    expect(weekStartFor(DateTime(2026, 11, 1, 9)), DateTime(2026, 10, 31));
    expect(weekStartFor(DateTime(2027, 1, 1, 9)), DateTime(2026, 12, 31));
  });
}
