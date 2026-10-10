import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/core/di/repository_provider.dart';
import 'package:vikunja_app/core/network/response.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/domain/entities/task_page_model.dart';
import 'package:vikunja_app/domain/entities/user.dart';
import 'package:vikunja_app/domain/repositories/project_repository.dart';
import 'package:vikunja_app/presentation/manager/task_page_controller.dart';
import 'package:vikunja_app/presentation/pages/task/task_list_page.dart';
import 'package:vikunja_app/presentation/widgets/task/add_task_dialog.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';

class MockTaskPageController extends TaskPageController {
  final TaskPageModel model;
  MockTaskPageController(this.model);

  @override
  Future<TaskPageModel> build() async => model;
}

class FakeProjectRepository extends Fake implements ProjectRepository {
  final List<Project> projects;
  FakeProjectRepository(this.projects);

  @override
  Future<Response<List<Project>>> getAll({
    int page = 1,
    String? search,
  }) async => SuccessResponse(projects, 200, {});
}

void main() {
  testWidgets('TaskListPage displays subproject title in task subtitle', (
    WidgetTester tester,
  ) async {
    final user = User(username: 'testuser');
    final subproject = Project(
      id: 2,
      title: 'Subproject A',
      parentProjectId: 1,
    );

    final task = Task(
      id: 101,
      title: 'Task in Subproject',
      createdBy: user,
      projectId: 2,
    );
    task.project = subproject;

    final model = TaskPageModel([task], false, 1, false);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskPageControllerProvider.overrideWith(
            () => MockTaskPageController(model),
          ),
        ],
        child: MaterialApp(
          home: const TaskListPage(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );

    await tester.pump();

    // Verify task title is displayed
    expect(find.text('Task in Subproject'), findsOneWidget);

    // Verify subproject title is displayed in the subtitle
    expect(find.text('Subproject A'), findsOneWidget);

    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('TaskListPage shows no results for an empty search', (
    WidgetTester tester,
  ) async {
    final model = TaskPageModel([], false, 1, false, searchQuery: 'missing');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskPageControllerProvider.overrideWith(
            () => MockTaskPageController(model),
          ),
        ],
        child: MaterialApp(
          home: const TaskListPage(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets(
    'FAB never offers a saved filter, even when it is the default project',
    (WidgetTester tester) async {
      // Default project id -5 is a saved filter (a pseudo-project).
      final model = TaskPageModel([], false, -5, false);
      final savedFilter = Project(id: -5, title: 'My filter');
      final realProject = Project(id: 3, title: 'Inbox');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskPageControllerProvider.overrideWith(
              () => MockTaskPageController(model),
            ),
            projectRepositoryProvider.overrideWithValue(
              FakeProjectRepository([savedFilter, realProject]),
            ),
          ],
          child: MaterialApp(
            home: const TaskListPage(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final dialog = tester.widget<AddTaskDialog>(find.byType(AddTaskDialog));
      expect(dialog.initialProjectId, 3);
      expect(dialog.projects.map((p) => p.id), [3]);
    },
  );
}
