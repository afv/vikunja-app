import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vikunja_app/core/di/repository_provider.dart';
import 'package:vikunja_app/core/network/response.dart';
import 'package:vikunja_app/domain/entities/label.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/domain/repositories/project_repository.dart';
import 'package:vikunja_app/domain/repositories/settings_repository.dart';
import 'package:vikunja_app/domain/repositories/task_repository.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/pages/calendar_page.dart';
import 'package:vikunja_app/presentation/widgets/task/add_task_dialog.dart';

class FakeProjects extends Fake implements ProjectRepository {
  @override
  Future<Response<List<Project>>> getAll({int page = 1, String? search}) async =>
      SuccessResponse([Project(id: 1, title: 'Casa'), Project(id: 2, title: 'Aveiro')], 200, {});
}

class FakeSettings extends Fake implements SettingsRepository {
  String? stored;
  FakeSettings([this.stored]);

  @override
  Future<String?> getCalendarFilters() async => stored;

  @override
  Future<void> setCalendarFilters(String json) async => stored = json;
}

class FakeTasks extends Fake implements TaskRepository {
  final List<String> filters = [];
  final List<Task> updated = [];
  final List<Task> added = [];
  final List<Task> tasks;
  FakeTasks(this.tasks);

  @override
  Future<Response<List<Task>>> getByFilterString(
    String filterString, [
    Map<String, List<String>>? queryParameters,
  ]) async {
    filters.add(filterString);
    return SuccessResponse(tasks, 200, {});
  }

  @override
  Future<Response<Task>> add(int projectId, Task task) async {
    added.add(task);
    return SuccessResponse(task, 201, {});
  }

  @override
  Future<Response<Task>> update(Task task) async {
    updated.add(task);
    return SuccessResponse(task, 200, {});
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('en'));

  Future<FakeTasks> pump(WidgetTester tester, [FakeSettings? settings]) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final fake = FakeTasks([
      Task(
        id: 1,
        title: 'Aspirar a casa',
        createdBy: null,
        projectId: 1,
        dueDate: DateTime(now.year, now.month, 15, 10),
        labels: [Label(id: 5, title: 'limpeza')],
      ),
      Task(id: 3, title: 'Tarefa de hoje', createdBy: null, projectId: 1, dueDate: DateTime(now.year, now.month, now.day, 12)),
      Task(id: 2, title: 'Regar plantas', createdBy: null, projectId: 2, dueDate: DateTime(now.year, now.month, 15, 18)),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(fake),
          projectRepositoryProvider.overrideWithValue(FakeProjects()),
          settingsRepositoryProvider.overrideWithValue(settings ?? FakeSettings()),
        ],
        child: MaterialApp(
          home: const CalendarPage(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('shows the tasks due this month and asks the server for a date range', (tester) async {
    final fake = await pump(tester);
    expect(find.text('Aspirar a casa'), findsOneWidget);
    expect(find.text('Regar plantas'), findsOneWidget);
    expect(fake.filters.first, contains('due_date >='));
    expect(fake.filters.first, contains('done = false'));
  });

  testWidgets('hiding a project in the filter sheet removes its tasks', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aveiro'));
    await tester.pumpAndSettle();
    // applied at once, without closing the sheet
    await tester.pumpAndSettle();
    expect(find.text('Aspirar a casa'), findsOneWidget);
    expect(find.text('Regar plantas'), findsNothing);
  });

  testWidgets('the agenda view shows the project and the labels', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Casa'), findsWidgets);
    expect(find.text('limpeza'), findsOneWidget);
  });

  testWidgets('a filter change is saved, and a saved one is applied on the next start', (tester) async {
    final settings = FakeSettings();
    await pump(tester, settings);
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aveiro'));
    await tester.pumpAndSettle();
    expect(settings.stored, contains('"hiddenProjects":[2]'));

    // a new page, as after restarting the app
    await tester.pumpWidget(const SizedBox());
    await pump(tester, FakeSettings(settings.stored));
    expect(find.text('Aspirar a casa'), findsOneWidget);
    expect(find.text('Regar plantas'), findsNothing);
  });

  testWidgets('week and day show the task columns, starting on this week and on today', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // the week opens on its Monday; a task of the 15th is within the three columns only when the 15th is near
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - DateTime.monday));
    expect(find.text('${monday.day}'), findsWidgets);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('${now.day}'), findsWidgets);
  });

  testWidgets("the day view lists today's tasks with their project", (tester) async {
    await pump(tester);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('Tarefa de hoje'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget); // the project path under the title
  });

  testWidgets('a long press on a day makes a task due that day, with the day preset', (tester) async {
    final fake = await pump(tester);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.longPressAt(tester.getBottomRight(find.byType(PageView)) - const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.byType(AddTaskDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Comprar pão');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(fake.added.single.title, 'Comprar pão');
    expect(fake.added.single.dueDate, DateTime(now.year, now.month, now.day, 9));
  });
}
