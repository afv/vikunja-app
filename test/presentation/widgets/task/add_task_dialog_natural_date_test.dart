import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/widgets/task/add_task_dialog.dart';

class AddedTask {
  String? title;
  DateTime? due;
  int calls = 0;
}

Future<AddedTask> pumpDialog(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final added = AddedTask();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: AddTaskDialog(
          projects: [Project(id: 1, title: 'Personal')],
          initialProjectId: 1,
          onAddTask: (title, dueDate, projectId, priority) {
            added.title = title;
            added.due = dueDate;
            added.calls++;
          },
        ),
      ),
    ),
  );
  return added;
}

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

final chip = find.byKey(const Key('natural-date-chip'));
final keptChip = find.byKey(const Key('natural-date-kept-chip'));

DateTime tomorrowAt(int hour, [int minute = 0]) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1, hour, minute);
}

void main() {
  testWidgets('shows no chip for a title without a date', (tester) async {
    await pumpDialog(tester);
    await type(tester, 'buy milk');
    expect(chip, findsNothing);
    expect(keptChip, findsNothing);
  });

  testWidgets('shows a chip with the date as soon as the phrase is typed', (
    tester,
  ) async {
    await pumpDialog(tester);
    await type(tester, 'do something');
    expect(chip, findsNothing);

    await type(tester, 'do something amanhã às 12');
    expect(chip, findsOneWidget);
    final label = tester.widget<InputChip>(chip).label as Text;
    expect(label.data, contains('Due'));
    expect(label.data, contains('12:00'));
    expect(label.data, contains('«amanhã às 12»'));
  });

  testWidgets('adds the title without the phrase, due at the date it names', (
    tester,
  ) async {
    final added = await pumpDialog(tester);
    await type(tester, 'do something amanhã às 12');
    await tester.tap(find.text('Add'));
    expect(added.title, 'Do something');
    expect(added.due, tomorrowAt(12));
  });

  testWidgets('reads English too, whatever the app language', (tester) async {
    final added = await pumpDialog(tester, locale: const Locale('pt', 'PT'));
    await type(tester, 'pay rent tomorrow at 5pm');
    expect(chip, findsOneWidget);
    await tester.tap(
      find.text('Add'),
    ); // not translated in pt-PT yet: English fallback
    expect(added.title, 'Pay rent');
    expect(added.due, tomorrowAt(17));
  });

  testWidgets(
    'tapping the chip keeps the words as text, and the due date is not set',
    (tester) async {
      final added = await pumpDialog(tester);
      await type(tester, 'do something amanhã às 12');
      await tester.tap(chip);
      await tester.pump();

      expect(chip, findsNothing);
      expect(keptChip, findsOneWidget);
      expect(
        (tester.widget<ActionChip>(keptChip).label as Text).data,
        '«amanhã às 12» kept as text',
      );

      await tester.tap(find.text('Add'));
      expect(added.title, 'Do something amanhã às 12');
      expect(added.due, isNull);
    },
  );

  testWidgets('the cross on the chip keeps the words as text too', (
    tester,
  ) async {
    final added = await pumpDialog(tester);
    await type(tester, 'do something amanhã às 12');
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(Icons.close)),
    );
    await tester.pump();
    expect(keptChip, findsOneWidget);

    await tester.tap(find.text('Add'));
    expect(added.title, 'Do something amanhã às 12');
    expect(added.due, isNull);
  });

  testWidgets('tapping the kept chip reads the words as a date again', (
    tester,
  ) async {
    final added = await pumpDialog(tester);
    await type(tester, 'do something amanhã às 12');
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(keptChip);
    await tester.pump();

    expect(keptChip, findsNothing);
    expect(chip, findsOneWidget);

    await tester.tap(find.text('Add'));
    expect(added.title, 'Do something');
    expect(added.due, tomorrowAt(12));
  });

  testWidgets(
    'keeping one phrase as text still lets a phrase typed later become the date',
    (tester) async {
      final added = await pumpDialog(tester);
      await type(tester, 'ligar amanhã');
      await tester.tap(chip);
      await tester.pump();
      expect(keptChip, findsOneWidget);

      await type(tester, 'ligar amanhã e depois em 3 dias');
      expect(chip, findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(added.title, 'Ligar amanhã e depois');
      final now = DateTime.now();
      final inThreeDays = DateTime(now.year, now.month, now.day + 3);
      expect(
        [added.due!.year, added.due!.month, added.due!.day],
        [inThreeDays.year, inThreeDays.month, inThreeDays.day],
      );
    },
  );

  testWidgets(
    'a due option chosen in the dialog wins, and the phrase is still cut from the title',
    (tester) async {
      final added = await pumpDialog(tester);
      await type(tester, 'do it amanhã às 12');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AddTaskDialog)),
      );
      await tester.tap(find.text(l10n.dueInOneWeek));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      final due = added.due!;
      final now = DateTime.now();
      final inAWeek = DateTime(now.year, now.month, now.day + 7);
      expect(
        [due.year, due.month, due.day],
        [inAWeek.year, inAWeek.month, inAWeek.day],
      );
      expect(added.title, 'Do it');
    },
  );

  testWidgets('choosing no due date on purpose also wins over the phrase', (
    tester,
  ) async {
    final added = await pumpDialog(tester);
    await type(tester, 'do it amanhã às 12');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AddTaskDialog)),
    );
    await tester.tap(find.text(l10n.dueOptionNone));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    expect(added.due, isNull);
    expect(added.title, 'Do it');
  });

  testWidgets(
    'shows no chip for a title that is only a date, and keeps it as the title',
    (tester) async {
      final added = await pumpDialog(tester);
      await type(tester, 'amanhã');
      expect(chip, findsNothing);
      await tester.tap(find.text('Add'));
      expect(added.title, 'Amanhã');
      expect(added.due, isNull);
    },
  );

  testWidgets('does not add a task with an empty title', (tester) async {
    final added = await pumpDialog(tester);
    await type(tester, '   ');
    await tester.tap(find.text('Add'), warnIfMissed: false);
    expect(added.calls, 0);
  });
}
