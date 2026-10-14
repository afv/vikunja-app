import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';

/// How long a task is drawn on the calendar: a task has a due date, not a duration.
const calendarEventLength = Duration(minutes: 30);

/// Same colour as the web calendar: the project's own, or a stable one derived from its id (golden-angle hues keep
/// neighbours apart), so the filter sheet's swatches double as the legend.
Color colorForProject(int id, [Color? own]) {
  if (own != null) return own;
  return HSLColor.fromAHSL(1, (id * 137.508) % 360, 0.55, 0.48).toColor();
}

class ProjectNode {
  final Project project;
  final List<ProjectNode> children;

  ProjectNode(this.project, this.children);
}

/// The projects as a tree. Saved filters (id <= 0) and archived projects are left out; a project whose parent is not
/// in the list becomes a root. Siblings by position, then title. Cycles are cut.
List<ProjectNode> buildProjectTree(List<Project> projects) {
  final real = projects.where((p) => p.id > 0 && !p.isArchived).toList();
  final ids = real.map((p) => p.id).toSet();
  final byParent = <int, List<Project>>{};
  for (final project in real) {
    final parent = ids.contains(project.parentProjectId)
        ? project.parentProjectId
        : 0;
    byParent.putIfAbsent(parent, () => []).add(project);
  }

  List<ProjectNode> build(int parent, Set<int> seen) {
    final siblings = (byParent[parent] ?? [])
      ..sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.title.compareTo(b.title);
      });
    return [
      for (final project in siblings)
        if (!seen.contains(project.id))
          ProjectNode(project, build(project.id, {...seen, project.id})),
    ];
  }

  return build(0, {});
}

/// The node's own id and every id below it.
List<int> subtreeIds(ProjectNode node) => [
  node.project.id,
  for (final child in node.children) ...subtreeIds(child),
];

enum NodeState { checked, unchecked, indeterminate }

/// Checked when the node and everything below it is shown, unchecked when all of it is hidden, else indeterminate.
NodeState nodeState(ProjectNode node, Set<int> hidden) {
  final ids = subtreeIds(node);
  final hiddenCount = ids.where(hidden.contains).length;
  if (hiddenCount == 0) return NodeState.checked;
  return hiddenCount == ids.length
      ? NodeState.unchecked
      : NodeState.indeterminate;
}

/// The hidden set after (un)checking a node: the whole subtree follows. Does not touch the set it is given.
Set<int> setNodeVisible(ProjectNode node, bool visible, Set<int> hidden) {
  final next = {...hidden};
  for (final id in subtreeIds(node)) {
    visible ? next.remove(id) : next.add(id);
  }
  return next;
}

/// Show everything, or hide everything.
Set<int> setAllVisible(List<ProjectNode> tree, bool visible) => visible
    ? <int>{}
    : {for (final node in tree) ...subtreeIds(node)};

/// Project titles from the root down to the project: «Aveiro › Cozinha». Guards against cycles.
List<String> projectPath(List<Project> projects, int projectId) {
  final byId = {for (final p in projects) p.id: p};
  final path = <String>[];
  final seen = <int>{};
  var current = byId[projectId];
  while (current != null && seen.add(current.id)) {
    path.insert(0, current.title);
    current = byId[current.parentProjectId];
  }
  return path;
}

class CalendarFilters {
  /// Projects switched off in the sheet. Switched off rather than on, so a new project shows up by default.
  final Set<int> hiddenProjects;

  /// Labels picked in the sheet; a task needs at least one of them. Empty = no label filter.
  final Set<int> labels;
  final bool colorByProject;
  final bool showDone;

  const CalendarFilters({
    this.hiddenProjects = const {},
    this.labels = const {},
    this.colorByProject = false,
    this.showDone = false,
  });

  CalendarFilters copyWith({
    Set<int>? hiddenProjects,
    Set<int>? labels,
    bool? colorByProject,
    bool? showDone,
  }) => CalendarFilters(
    hiddenProjects: hiddenProjects ?? this.hiddenProjects,
    labels: labels ?? this.labels,
    colorByProject: colorByProject ?? this.colorByProject,
    showDone: showDone ?? this.showDone,
  );

  Map<String, dynamic> toJson() => {
    'hiddenProjects': hiddenProjects.toList(),
    'labels': labels.toList(),
    'colorByProject': colorByProject,
    'showDone': showDone,
  };

  /// Whatever comes out of storage becomes a valid state; garbage falls back to the defaults.
  factory CalendarFilters.fromJson(Object? json) {
    if (json is! Map) return const CalendarFilters();
    Set<int> ids(Object? v) => v is List ? v.whereType<int>().toSet() : <int>{};
    return CalendarFilters(
      hiddenProjects: ids(json['hiddenProjects']),
      labels: ids(json['labels']),
      colorByProject: json['colorByProject'] == true,
      showDone: json['showDone'] == true,
    );
  }

  bool isVisible(Task task) {
    if (task.projectId != null && hiddenProjects.contains(task.projectId)) {
      return false;
    }
    if (labels.isEmpty) return true;
    return task.labels.any((label) => labels.contains(label.id));
  }
}

class LabelUse {
  final int id;
  final String title;
  final Color? color;
  final int count;

  LabelUse(this.id, this.title, this.color, this.count);
}

/// The labels carried by these tasks, with how many tasks carry each; most used first, then by title.
List<LabelUse> labelsInUse(Iterable<Task> tasks) {
  final found = <int, LabelUse>{};
  for (final task in tasks) {
    for (final label in task.labels) {
      final known = found[label.id];
      found[label.id] = LabelUse(
        label.id,
        label.title,
        label.color,
        (known?.count ?? 0) + 1,
      );
    }
  }
  return found.values.toList()..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.title.compareTo(b.title);
  });
}

/// The due date filter for a visible range, as the API wants it: whole days, in UTC.
String dueDateRangeFilter(DateTime start, DateTime end, {bool showDone = false}) {
  String iso(DateTime d) => d.toUtc().toIso8601String();
  return [
    if (!showDone) 'done = false',
    'due_date >= ${iso(start)}',
    'due_date < ${iso(end)}',
  ].join(' && ');
}

/// Where a task lands on the calendar after being dropped on [start]: the new due date keeps the shape of the old
/// one. Returns null when the drop did not move the task.
DateTime? rescheduledDue(Task task, DateTime start) {
  final due = task.dueDate;
  if (due == null) return null;
  return due.isAtSameMomentAs(start) ? null : start;
}
