import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/core/utils/calendar.dart';
import 'package:vikunja_app/domain/entities/label.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';

// Casa (1) > Arrumar (2) > Sala (3), Cozinha (4);  Casa (1) > Manutenção (5);  Aveiro (6) > Limpeza (7)
final projects = [
  Project(id: 1, title: 'Casa', position: 100, color: const Color(0xFF37474F)),
  Project(id: 2, title: 'Arrumar', parentProjectId: 1, position: 100),
  Project(id: 3, title: 'Sala', parentProjectId: 2, position: 200),
  Project(id: 4, title: 'Cozinha', parentProjectId: 2, position: 100),
  Project(id: 5, title: 'Manutenção', parentProjectId: 1, position: 200),
  Project(id: 6, title: 'Aveiro', position: 200),
  Project(id: 7, title: 'Limpeza', parentProjectId: 6),
  Project(id: -3, title: 'Saved filter'),
  Project(id: 8, title: 'Old', isArchived: true),
];

Task task(int project, {List<Label> labels = const [], DateTime? due}) => Task(
  id: 1,
  title: 't',
  createdBy: null,
  projectId: project,
  labels: labels,
  dueDate: due,
);

void main() {
  final tree = buildProjectTree(projects);
  final casa = tree[0];
  final arrumar = casa.children[0];

  group('buildProjectTree', () {
    test('nests children and orders siblings by position', () {
      expect(tree.map((n) => n.project.title), ['Casa', 'Aveiro']);
      expect(casa.children.map((n) => n.project.title), [
        'Arrumar',
        'Manutenção',
      ]);
      expect(arrumar.children.map((n) => n.project.title), ['Cozinha', 'Sala']);
    });

    test('leaves out saved filters and archived projects', () {
      final ids = tree.expand(subtreeIds).toList();
      expect(ids, isNot(contains(-3)));
      expect(ids, isNot(contains(8)));
    });

    test('a project with a missing parent becomes a root', () {
      final orphan = buildProjectTree([
        Project(id: 9, title: 'O', parentProjectId: 99),
      ]);
      expect(orphan.single.project.id, 9);
    });

    test('does not loop on a cycle', () {
      final cyclic = buildProjectTree([
        Project(id: 1, title: 'A', parentProjectId: 2),
        Project(id: 2, title: 'B', parentProjectId: 1),
      ]);
      expect(cyclic, isEmpty);
    });
  });

  group('colorForProject', () {
    test(
      'keeps its own colour, derives a stable and distinct one otherwise',
      () {
        expect(
          colorForProject(1, const Color(0xFFFF0000)),
          const Color(0xFFFF0000),
        );
        expect(colorForProject(7), colorForProject(7));
        expect({for (var i = 1; i <= 8; i++) colorForProject(i)}.length, 8);
      },
    );
  });

  group('checkbox state', () {
    test('checked when nothing below is hidden', () {
      expect(nodeState(casa, {}), NodeState.checked);
    });

    test('unchecked when all hidden, indeterminate when part is', () {
      expect(nodeState(arrumar, {2, 3, 4}), NodeState.unchecked);
      expect(nodeState(casa, {2, 3, 4}), NodeState.indeterminate);
      expect(nodeState(arrumar, {3}), NodeState.indeterminate);
    });

    test('hides and shows a whole subtree without touching the given set', () {
      final before = {5};
      final hidden = setNodeVisible(arrumar, false, before);
      expect(hidden, {2, 3, 4, 5});
      expect(before, {5});
      expect(setNodeVisible(arrumar, true, hidden), {5});
    });

    test('all or none', () {
      expect(setAllVisible(tree, true), isEmpty);
      expect(setAllVisible(tree, false), {1, 2, 3, 4, 5, 6, 7});
    });
  });

  group('CalendarFilters.isVisible', () {
    final labels = [Label(id: 10, title: 'a'), Label(id: 11, title: 'b')];

    test('hides tasks of hidden projects', () {
      expect(
        const CalendarFilters(hiddenProjects: {3}).isVisible(task(3)),
        isFalse,
      );
      expect(
        const CalendarFilters(hiddenProjects: {4}).isVisible(task(3)),
        isTrue,
      );
    });

    test('with labels picked, needs at least one of them', () {
      final t = task(3, labels: labels);
      expect(const CalendarFilters(labels: {11, 99}).isVisible(t), isTrue);
      expect(const CalendarFilters(labels: {99}).isVisible(t), isFalse);
      expect(const CalendarFilters(labels: {10}).isVisible(task(3)), isFalse);
    });
  });

  test('projectPath lists titles from the root down and survives a cycle', () {
    expect(projectPath(projects, 4), ['Casa', 'Arrumar', 'Cozinha']);
    expect(projectPath(projects, 404), isEmpty);
    expect(
      projectPath([
        Project(id: 1, title: 'A', parentProjectId: 2),
        Project(id: 2, title: 'B', parentProjectId: 1),
      ], 1),
      ['B', 'A'],
    );
  });

  test('labelsInUse counts tasks per label, most used first', () {
    final jardim = Label(id: 2, title: 'jardim');
    final used = labelsInUse([
      task(
        1,
        labels: [
          Label(id: 1, title: 'sítio'),
          jardim,
        ],
      ),
      task(1, labels: [jardim]),
      task(1),
    ]);
    expect(used.map((l) => (l.title, l.count)), [('jardim', 2), ('sítio', 1)]);
  });

  test(
    'dueDateRangeFilter is in UTC and leaves out finished tasks unless asked',
    () {
      final start = DateTime.utc(2026, 10, 1);
      final end = DateTime.utc(2026, 11, 1);
      expect(
        dueDateRangeFilter(start, end),
        'done = false && due_date >= 2026-10-01T00:00:00.000Z && due_date < 2026-11-01T00:00:00.000Z',
      );
      expect(
        dueDateRangeFilter(start, end, showDone: true),
        isNot(contains('done')),
      );
    },
  );

  test('rescheduledDue is null when the task did not move', () {
    final due = DateTime.utc(2026, 10, 12, 10);
    expect(rescheduledDue(task(1, due: due), due), isNull);
    expect(
      rescheduledDue(task(1, due: due), due.add(const Duration(days: 1))),
      due.add(const Duration(days: 1)),
    );
    expect(rescheduledDue(task(1), due), isNull);
  });

  test(
    'filters survive a round trip through JSON, and garbage gives the defaults',
    () {
      const f = CalendarFilters(
        hiddenProjects: {3, 4},
        labels: {10},
        colorByProject: true,
        showDone: true,
      );
      final back = CalendarFilters.fromJson(f.toJson());
      expect(back.hiddenProjects, {3, 4});
      expect(back.labels, {10});
      expect(back.colorByProject, isTrue);
      expect(back.showDone, isTrue);
      final bad = CalendarFilters.fromJson('nope');
      expect(bad.hiddenProjects, isEmpty);
      expect(bad.labels, isEmpty);
      expect(bad.colorByProject, isFalse);
      expect(
        CalendarFilters.fromJson({
          'hiddenProjects': 'x',
          'labels': [1, 'a'],
        }).labels,
        {1},
      );
    },
  );

  test('combineFilter brackets the saved expression and adds the range', () {
    expect(
      combineFilter('done = false || priority >= 4', 'due_date >= a'),
      '(done = false || priority >= 4) && due_date >= a',
    );
    expect(combineFilter('  ', 'due_date >= a'), 'due_date >= a');
  });

  test(
    'savedFilterId maps the pseudo-project id to the filter id, and real projects to 0',
    () {
      expect(savedFilterId(-15), 14);
      expect(savedFilterId(-2), 1);
      expect(savedFilterId(-1), 0); // favourites
      expect(savedFilterId(0), 0);
      expect(savedFilterId(7), 0);
    },
  );

  test('the source survives JSON and a bad one is dropped', () {
    expect(
      CalendarFilters.fromJson(
        const CalendarFilters(source: 14).toJson(),
      ).source,
      14,
    );
    expect(CalendarFilters.fromJson({'source': -3}).source, 0);
    expect(CalendarFilters.fromJson({'source': '14'}).source, 0);
  });
}
