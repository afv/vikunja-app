import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/presentation/manager/task_page_controller.dart';

void main() {
  test('the home list follows the overview filter', () {
    expect(overviewFilterForQuery(-7, ''), -7);
    expect(overviewFilterForQuery(-7, '   '), -7);
  });

  test('a search looks through every task, not only the overview filter', () {
    // «📅 Porto — próximos» only holds tasks due in 14 days: «calda» (due in months) must still be found.
    expect(overviewFilterForQuery(-7, 'calda'), isNull);
  });

  test('no overview filter set: always every task', () {
    expect(overviewFilterForQuery(null, ''), isNull);
    expect(overviewFilterForQuery(0, ''), isNull);
    expect(overviewFilterForQuery(null, 'calda'), isNull);
  });
}
