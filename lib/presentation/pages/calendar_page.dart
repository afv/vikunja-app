import 'dart:convert';
import 'dart:developer' as developer;

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
import 'package:vikunja_app/presentation/widgets/calendar/calendar_days.dart';
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
      TaskEvent(task: task, color: color, path: path, start: start, end: end);

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
  int get hashCode =>
      Object.hash(super.hashCode, task.id, task.title, task.done, color, path);
}

/// Month and agenda come from kalender; week and day are our own day columns (see [CalendarDays]).
enum CalendarMode { month, week, day, agenda }

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

  CalendarMode _mode = CalendarMode.month;
  final _daysKey = GlobalKey<CalendarDaysState>();
  late DateTime _daysStart = DateTime.now();
  DateTimeRange? _daysRange;
  final _daysFocus = ValueNotifier<DateTime>(DateTime.now());
  List<TaskEvent> _taskEvents = [];

  bool get _custom => _mode == CalendarMode.week || _mode == CalendarMode.day;

  /// What is on screen right now, whichever view is showing it.
  DateTimeRange get _currentRange {
    if (_custom) {
      return _daysRange ??
          DateTimeRange(
            start: _daysStart,
            end: _daysStart.add(const Duration(days: 7)),
          );
    }
    final visible = _controller.visibleDateTimeRange.value;
    return DateTimeRange(start: visible.start, end: visible.end);
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _restoreFilters();
      _load();
    });
  }

  @override
  void dispose() {
    _controller.visibleDateTimeRange.removeListener(_onRangeChanged);
    _controller.dispose();
    _events.dispose();
    _daysFocus.dispose();
    super.dispose();
  }

  void _onRangeChanged() {
    if (_custom) return;
    final visible = _controller.visibleDateTimeRange.value;
    _rangeChanged(DateTimeRange(start: visible.start, end: visible.end));
  }

  void _rangeChanged(DateTimeRange visible) {
    final loaded = _loaded;
    if (loaded != null &&
        !visible.start.isBefore(loaded.start) &&
        !visible.end.isAfter(loaded.end)) {
      return; // already have it
    }
    // The range changes while KalenderView builds; loading (and its setState) has to wait for the frame to end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  /// A month either side of what is visible, so paging back and forth does not wait on the network every time.
  DateTimeRange _wanted() {
    final visible = _currentRange;
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
    try {
      for (var page = 1; page <= _maxPages; page++) {
        final response = await ref
            .read(taskRepositoryProvider)
            .getByFilterString(
              dueDateRangeFilter(
                wanted.start,
                wanted.end,
                showDone: _filters.showDone,
              ),
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
    } catch (e, st) {
      // Whatever went wrong, the spinner must stop and the retry banner must show.
      developer.log('calendar load failed: $e', stackTrace: st);
      ok = false;
    }

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
      final response = await ref
          .read(projectRepositoryProvider)
          .getAll(page: page);
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
      if (!task.hasDueDate || due == null || !_filters.isVisible(task)) {
        continue;
      }
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
    setState(() => _taskEvents = events);
  }

  /// Switching view keeps the date the old view started on, which for the month is the first grid cell (28 September
  /// in October), not what the user is looking at. Land on today when it is on screen, else the middle of the range.
  void _switchTo(CalendarMode mode) {
    final visible = _currentRange;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inView =
        !today.isBefore(visible.start) && today.isBefore(visible.end);
    final focus = inView
        ? today
        : visible.start.add(
            Duration(
              microseconds:
                  visible.end.difference(visible.start).inMicroseconds ~/ 2,
            ),
          );
    setState(() {
      _mode = mode;
      // the week opens on its Monday; scrolling from there goes day by day
      _daysStart = mode == CalendarMode.week
          ? mondayOf(focus)
          : DateTime(focus.year, focus.month, focus.day);
      _daysRange = null;
      _daysFocus.value = _daysStart;
    });
    if (!_custom) {
      _controller.viewConfiguration = mode == CalendarMode.month
          ? _month
          : _agenda;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.jumpToDate(focus);
      });
    }
  }

  void _today() {
    final now = DateTime.now();
    if (!_custom) {
      _controller.animateToDate(now);
      return;
    }
    _daysKey.currentState?.animateTo(
      _mode == CalendarMode.week ? mondayOf(now) : now,
    );
  }

  void _step(int direction) {
    if (!_custom) {
      direction < 0
          ? _controller.animateToPreviousPage()
          : _controller.animateToNextPage();
      return;
    }
    _daysKey.currentState?.shift(
      direction * (_mode == CalendarMode.week ? 7 : 1),
    );
  }

  Future<void> _openFilters() async {
    await showCalendarFilters(
      context,
      projects: _projects,
      tasks: _tasks,
      filters: _filters,
      onChanged: (changed) {
        if (!mounted) return;
        final reload = changed.showDone != _filters.showDone;
        setState(() => _filters = changed);
        _saveFilters(changed);
        reload ? _load() : _refreshEvents();
      },
    );
  }

  Future<void> _restoreFilters() async {
    try {
      final stored = await ref
          .read(settingsRepositoryProvider)
          .getCalendarFilters();
      if (stored != null && mounted) {
        _filters = CalendarFilters.fromJson(jsonDecode(stored));
      }
    } catch (_) {
      // no stored filters, or unreadable ones: start with the defaults
    }
  }

  Future<void> _saveFilters(CalendarFilters filters) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setCalendarFilters(jsonEncode(filters.toJson()));
    } catch (_) {
      // best effort: the filters still apply for this session
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
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.calendarRescheduleError)),
      );
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
    final filtering =
        _filters.hiddenProjects.isNotEmpty || _filters.labels.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: _custom
            ? ValueListenableBuilder(
                valueListenable: _daysFocus,
                builder: (context, day, _) => Text(_monthTitle(context, day)),
              )
            : ValueListenableBuilder(
                valueListenable: _controller.floatingVisibleRange,
                builder: (context, range, _) =>
                    Text(_monthTitle(context, range.dominantMonthDate)),
              ),
        actions: [
          IconButton(
            tooltip: l10n.calendarToday,
            icon: const Icon(Icons.today),
            onPressed: _today,
          ),
          IconButton(
            tooltip: l10n.calendarPrevious,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _step(-1),
          ),
          IconButton(
            tooltip: l10n.calendarNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _step(1),
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
            child: SegmentedButton<CalendarMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: CalendarMode.month,
                  label: Text(l10n.calendarMonth),
                ),
                ButtonSegment(
                  value: CalendarMode.week,
                  label: Text(l10n.calendarWeek),
                ),
                ButtonSegment(
                  value: CalendarMode.day,
                  label: Text(l10n.calendarDay),
                ),
                ButtonSegment(
                  value: CalendarMode.agenda,
                  label: Text(l10n.calendarAgenda),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) => _switchTo(selection.first),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_loading &&
              !_failed &&
              _loaded != null &&
              _taskEvents.isEmpty &&
              filtering)
            ListTile(
              dense: true,
              leading: const Icon(Icons.filter_alt_off_outlined),
              title: Text(l10n.calendarNothingMatches),
              trailing: TextButton(
                onPressed: () {
                  setState(
                    () => _filters = _filters.copyWith(
                      hiddenProjects: {},
                      labels: {},
                    ),
                  );
                  _saveFilters(_filters);
                  _refreshEvents();
                },
                child: Text(l10n.calendarClearFilters),
              ),
            ),
          if (_failed)
            MaterialBanner(
              backgroundColor: scheme.errorContainer,
              content: Text(l10n.calendarLoadError),
              actions: [TextButton(onPressed: _load, child: Text(l10n.retry))],
            ),
          Expanded(
            child: _custom
                ? CalendarDays(
                    key: ValueKey(_mode),
                    events: _taskEvents,
                    start: _daysStart,
                    columns: _mode == CalendarMode.week ? 3 : 1,
                    onTap: _open,
                    onVisibleDays: (start, end) {
                      _daysFocus.value = start;
                      _daysRange = DateTimeRange(start: start, end: end);
                      _rangeChanged(_daysRange!);
                    },
                  )
                : KalenderView(
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
                    components: KalenderComponents(
                      monthComponents: MonthComponents(
                        // «Wednesday» does not fit a phone's column and wraps onto a second line.
                        headerComponents: MonthHeaderComponents(
                          weekDayHeaderStringBuilder: (context, date) =>
                              DateFormat.E(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(date),
                        ),
                      ),
                    ),
                    views: [
                      MonthViewParts(
                        body: MonthBody(
                          tileComponents: TileComponents(tileBuilder: _tile),
                        ),
                      ),
                      ScheduleViewParts(
                        body: ScheduleBody(
                          tileComponents: ScheduleTileComponents(
                            tileBuilder: _agendaTile,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _monthTitle(BuildContext context, DateTime month) => DateFormat.yMMMM(
    Localizations.localeOf(context).toLanguageTag(),
  ).format(month);

  Widget _tile(
    BuildContext context,
    KalenderEvent event,
    KalenderDateTimeRange tileRange,
  ) {
    final e = event as TaskEvent;
    final foreground = e.color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
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

  Widget _agendaTile(
    BuildContext context,
    KalenderEvent event,
    KalenderDateTimeRange tileRange,
  ) {
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
