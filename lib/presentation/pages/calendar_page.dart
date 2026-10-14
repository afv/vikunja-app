import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kalender/kalender.dart';
import 'package:vikunja_app/core/di/repository_provider.dart';
import 'package:vikunja_app/core/utils/calendar.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/pages/task/task_detail_page.dart';
import 'package:vikunja_app/presentation/widgets/calendar/calendar_filters_sheet.dart';

/// A task on the calendar, at its due date. Recurring tasks show their next occurrence only, as the server stores it.
class TaskEvent extends KalenderEvent {
  final Task task;
  final Color color;
  final String path;

  TaskEvent({
    required this.task,
    required this.color,
    required this.path,
    required super.start,
    required super.end,
  }) : super(id: '${task.id}');

  @override
  TaskEvent copyWithData({required DateTime start, required DateTime end}) =>
      TaskEvent(
        task: task,
        color: color,
        path: path,
        start: start,
        end: end,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TaskEvent &&
          other.task.id == task.id &&
          other.task.title == task.title &&
          other.task.done == task.done &&
          other.color == color &&
          other.path == path;

  @override
  int get hashCode => Object.hash(super.hashCode, task.id, task.title, task.done, color, path);
}

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  static const _maxPages = 20;
  static const _pageSize = 50; // the server's default maximum page size

  final _month = MonthViewConfiguration.singleMonth();
  final _agenda = ScheduleViewConfiguration.continuous();
  final _events = DefaultEventsController();
  late final KalenderController _controller = KalenderController(
    viewConfiguration: _month,
  );

  CalendarFilters _filters = const CalendarFilters();
  List<Project> _projects = [];
  List<Task> _tasks = [];
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  DateTimeRange? _loaded;

  @override
  void initState() {
    super.initState();
    _controller.visibleDateTimeRange.addListener(_onRangeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.visibleDateTimeRange.removeListener(_onRangeChanged);
    _controller.dispose();
    _events.dispose();
    super.dispose();
  }

  void _onRangeChanged() {
    final visible = _controller.visibleDateTimeRange.value;
    final loaded = _loaded;
    if (loaded != null &&
        !visible.start.isBefore(loaded.start) &&
        !visible.end.isAfter(loaded.end)) {
      return; // already have it
    }
    _load();
  }

  /// A month either side of what is visible, so paging back and forth does not wait on the network every time.
  DateTimeRange _wanted() {
    final visible = _controller.visibleDateTimeRange.value;
    return DateTimeRange(
      start: DateTime(visible.start.year, visible.start.month - 1, 1),
      end: DateTime(visible.end.year, visible.end.month + 2, 1),
    );
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final wanted = _wanted();
    setState(() {
      _loading = true;
      _failed = false;
    });

    final tasks = <Task>[];
    var ok = true;
    for (var page = 1; page <= _maxPages; page++) {
      final response = await ref.read(taskRepositoryProvider).getByFilterString(
        dueDateRangeFilter(wanted.start, wanted.end, showDone: _filters.showDone),
        {
          'filter_include_nulls': ['false'],
          'sort_by': ['due_date', 'id'],
          'order_by': ['asc', 'asc'],
          'page': ['$page'],
          'per_page': ['$_pageSize'],
        },
      );
      if (!response.isSuccessful) {
        ok = false;
        break;
      }
      final batch = response.toSuccess().body;
      tasks.addAll(batch);
      if (batch.length < _pageSize) break;
    }
    if (_projects.isEmpty) await _loadProjects();

    if (!mounted || generation != _generation) return; // a newer load took over
    setState(() {
      _tasks = tasks;
      _loaded = ok ? wanted : null;
      _loading = false;
      _failed = !ok;
    });
    _refreshEvents();
  }

  Future<void> _loadProjects() async {
    final all = <Project>[];
    for (var page = 1; page <= _maxPages; page++) {
      final response = await ref.read(projectRepositoryProvider).getAll(page: page);
      if (!response.isSuccessful) break;
      final batch = response.toSuccess().body;
      all.addAll(batch);
      if (batch.length < _pageSize) break;
    }
    _projects = all;
  }

  void _refreshEvents() {
    final byId = {for (final p in _projects) p.id: p};
    final events = <TaskEvent>[];
    for (final task in _tasks) {
      final due = task.dueDate;
      if (!task.hasDueDate || due == null || !_filters.isVisible(task)) continue;
      final project = byId[task.projectId];
      final projectColor = colorForProject(task.projectId ?? 0, project?.color);
      final color = _filters.colorByProject
          ? projectColor
          : (task.color ?? Theme.of(context).colorScheme.primary);
      final start = due.toLocal();
      events.add(
        TaskEvent(
          task: task,
          color: color,
          path: projectPath(_projects, task.projectId ?? 0).join(' › '),
          start: start,
          end: start.add(calendarEventLength),
        ),
      );
    }
    _events.replaceEvents(events);
  }

  Future<void> _openFilters() async {
    final changed = await showCalendarFilters(
      context,
      projects: _projects,
      tasks: _tasks,
      filters: _filters,
    );
    if (changed == null || !mounted) return;
    final reload = changed.showDone != _filters.showDone;
    setState(() => _filters = changed);
    if (reload) {
      await _load();
    } else {
      _refreshEvents();
    }
  }

  Future<void> _reschedule(TaskEvent original, TaskEvent updated) async {
    final newDue = rescheduledDue(original.task, updated.start);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (newDue == null) return;
    final response = await ref
        .read(taskRepositoryProvider)
        .update(original.task.copyWith(dueDate: newDue));
    if (!mounted) return;
    if (response.isSuccessful) {
      final saved = response.toSuccess().body;
      final i = _tasks.indexWhere((t) => t.id == saved.id);
      if (i >= 0) _tasks[i] = saved;
      _refreshEvents();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l10n.calendarRescheduleError)));
      _refreshEvents(); // put the tile back where the server has it
    }
  }

  void _open(TaskEvent event) {
    Navigator.push<Task?>(
      context,
      MaterialPageRoute(builder: (_) => TaskDetailPage(task: event.task)),
    ).then((_) {
      if (mounted) _load(); // it may have been edited or finished there
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final filtering = _filters.hiddenProjects.isNotEmpty || _filters.labels.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder(
          valueListenable: _controller.floatingVisibleRange,
          builder: (context, range, _) {
            final month = range.dominantMonthDate;
            return Text(
              DateFormat.yMMMM(Localizations.localeOf(context).toLanguageTag()).format(month),
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: l10n.calendarToday,
            icon: const Icon(Icons.today),
            onPressed: () => _controller.animateToDate(DateTime.now()),
          ),
          IconButton(
            tooltip: l10n.calendarPrevious,
            icon: const Icon(Icons.chevron_left),
            onPressed: _controller.animateToPreviousPage,
          ),
          IconButton(
            tooltip: l10n.calendarNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: _controller.animateToNextPage,
          ),
          IconButton(
            tooltip: l10n.calendarFilters,
            icon: Badge(
              isLabelVisible: filtering,
              child: const Icon(Icons.filter_alt_outlined),
            ),
            onPressed: _openFilters,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => SegmentedButton<ViewConfiguration>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _month, label: Text(l10n.calendarMonth)),
                  ButtonSegment(value: _agenda, label: Text(l10n.calendarAgenda)),
                ],
                selected: {_controller.viewConfiguration},
                onSelectionChanged: (selection) =>
                    _controller.viewConfiguration = selection.first,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_failed)
            MaterialBanner(
              backgroundColor: scheme.errorContainer,
              content: Text(l10n.calendarLoadError),
              actions: [TextButton(onPressed: _load, child: Text(l10n.retry))],
            ),
          Expanded(
            child: KalenderView(
              eventsController: _events,
              kalenderController: _controller,
              locale: Localizations.localeOf(context),
              interaction: KalenderInteraction(
                allowResizing: false,
                allowEventCreation: false,
                // A tap opens the task; moving one takes a long press, so scrolling never moves a due date.
                modifyEventGesture: EventInteractionGesture.longPress,
              ),
              callbacks: KalenderCallbacks(
                onEventTapped: (event) {
                  if (event is TaskEvent) _open(event);
                },
                onEventChanged: (original, updated) {
                  if (original is TaskEvent && updated is TaskEvent) {
                    _reschedule(original, updated);
                  }
                },
              ),
              views: [
                MonthViewParts(
                  body: MonthBody(tileComponents: TileComponents(tileBuilder: _tile)),
                ),
                ScheduleViewParts(
                  body: ScheduleBody(
                    tileComponents: ScheduleTileComponents(tileBuilder: _agendaTile),
                  ),
                ),
                const MultiDayViewParts(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, KalenderEvent event, KalenderDateTimeRange tileRange) {
    final e = event as TaskEvent;
    final foreground = e.color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: e.color.withValues(alpha: e.task.done ? 0.45 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        e.task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: foreground,
          decoration: e.task.done ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  Widget _agendaTile(BuildContext context, KalenderEvent event, KalenderDateTimeRange tileRange) {
    final e = event as TaskEvent;
    final theme = Theme.of(context);
    final time = TimeOfDay.fromDateTime(e.start).format(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: e.color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            e.task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              decoration: e.task.done ? TextDecoration.lineThrough : null,
            ),
          ),
          Text(
            e.path.isEmpty ? time : '$time · ${e.path}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (e.task.labels.isNotEmpty)
            Wrap(
              spacing: 4,
              children: [
                for (final label in e.task.labels)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    label: Text(label.title, style: theme.textTheme.labelSmall),
                    backgroundColor: label.color,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
