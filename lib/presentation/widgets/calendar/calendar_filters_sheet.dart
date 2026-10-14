import 'package:flutter/material.dart';
import 'package:vikunja_app/core/utils/calendar.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';

/// The calendar's filter sheet: colour by task or project, finished tasks, the project tree, label chips.
/// Every change is reported through [onChanged] as it is made, so it applies however the sheet is closed.
Future<void> showCalendarFilters(
  BuildContext context, {
  required List<Project> projects,
  required List<Task> tasks,
  required CalendarFilters filters,
  required ValueChanged<CalendarFilters> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _FiltersBody(
        scroll: scroll,
        projects: projects,
        labels: labelsInUse(tasks),
        initial: filters,
        onChanged: onChanged,
      ),
    ),
  );
}

class _FiltersBody extends StatefulWidget {
  final ScrollController scroll;
  final List<Project> projects;
  final List<LabelUse> labels;
  final CalendarFilters initial;
  final ValueChanged<CalendarFilters> onChanged;

  const _FiltersBody({
    required this.scroll,
    required this.projects,
    required this.labels,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<_FiltersBody> createState() => _FiltersBodyState();
}

class _FiltersBodyState extends State<_FiltersBody> {
  late CalendarFilters _filters = widget.initial;
  late final List<ProjectNode> _tree = buildProjectTree(widget.projects);
  final Set<int> _collapsed = {};

  void _apply(CalendarFilters next) {
    setState(() => _filters = next);
    widget.onChanged(next);
  }

  Iterable<Widget> _rows(ProjectNode node, int depth) sync* {
    final state = nodeState(node, _filters.hiddenProjects);
    final open = !_collapsed.contains(node.project.id);
    yield Padding(
      padding: EdgeInsets.only(left: 12.0 * depth),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: node.children.isEmpty
                ? null
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
                    onPressed: () => setState(() {
                      open
                          ? _collapsed.add(node.project.id)
                          : _collapsed.remove(node.project.id);
                    }),
                  ),
          ),
          Expanded(
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              tristate: true,
              value: switch (state) {
                NodeState.checked => true,
                NodeState.unchecked => false,
                NodeState.indeterminate => null,
              },
              onChanged: (_) => _apply(
                _filters.copyWith(
                  hiddenProjects: setNodeVisible(
                    node,
                    state != NodeState.checked,
                    _filters.hiddenProjects,
                  ),
                ),
              ),
              title: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colorForProject(node.project.id, node.project.color),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(node.project.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (open) {
      for (final child in node.children) {
        yield* _rows(child, depth + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final heading = Theme.of(context).textTheme.labelLarge;
    return ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.calendarColorBy, style: heading),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(l10n.calendarColorTask)),
              ButtonSegment(value: true, label: Text(l10n.calendarColorProject)),
            ],
            selected: {_filters.colorByProject},
            onSelectionChanged: (s) => _apply(_filters.copyWith(colorByProject: s.first)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.calendarShowDone),
            value: _filters.showDone,
            onChanged: (v) => _apply(_filters.copyWith(showDone: v)),
          ),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text(l10n.calendarProjects, style: heading)),
              TextButton(
                onPressed: () => _apply(
                  _filters.copyWith(hiddenProjects: setAllVisible(_tree, true)),
                ),
                child: Text(l10n.calendarAll),
              ),
              TextButton(
                onPressed: () => _apply(
                  _filters.copyWith(hiddenProjects: setAllVisible(_tree, false)),
                ),
                child: Text(l10n.calendarNone),
              ),
            ],
          ),
          for (final node in _tree) ..._rows(node, 0),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text(l10n.calendarLabels, style: heading)),
              if (_filters.labels.isNotEmpty)
                TextButton(
                  onPressed: () => _apply(_filters.copyWith(labels: {})),
                  child: Text(l10n.calendarClear),
                ),
            ],
          ),
          if (widget.labels.isEmpty && _filters.labels.isEmpty)
            Text(l10n.calendarNoLabels)
          else
            Wrap(
              spacing: 6,
              children: [
                for (final label in widget.labels)
                  FilterChip(
                    label: Text('${label.title} · ${label.count}'),
                    avatar: CircleAvatar(
                      radius: 5,
                      backgroundColor: label.color ?? Theme.of(context).colorScheme.outline,
                    ),
                    selected: _filters.labels.contains(label.id),
                    onSelected: (on) => _apply(
                      _filters.copyWith(
                        labels: on
                            ? {..._filters.labels, label.id}
                            : ({..._filters.labels}..remove(label.id)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
    );
  }
}
