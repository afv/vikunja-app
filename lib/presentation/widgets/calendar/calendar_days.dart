import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vikunja_app/presentation/pages/calendar_page.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday of the week [d] is in.
DateTime mondayOf(DateTime d) =>
    _dayOf(d).subtract(Duration(days: d.weekday - DateTime.monday));

/// Week and day views: a row of day columns, each listing that day's tasks by time. It scrolls day by day (the week
/// view shows several columns and scrolls freely; the day view shows one and snaps), and it never squeezes tasks
/// into an hourly grid, where the many cards due at the same hour would be unreadable.
class CalendarDays extends StatefulWidget {
  final List<TaskEvent> events;

  /// The first column when the view opens.
  final DateTime start;

  /// How many days are on screen: 1 snaps one day at a time, more scrolls freely.
  final int columns;
  final ValueChanged<TaskEvent> onTap;

  /// A long press on a task: change its due date.
  final ValueChanged<TaskEvent> onLongPressEvent;

  /// A long press on a day's empty space: a new task on that day.
  final ValueChanged<DateTime> onLongPressDay;

  /// The days on screen changed (also once at the start): [start] to [end], end exclusive.
  final void Function(DateTime start, DateTime end) onVisibleDays;

  const CalendarDays({
    super.key,
    required this.events,
    required this.start,
    required this.columns,
    required this.onTap,
    required this.onLongPressEvent,
    required this.onLongPressDay,
    required this.onVisibleDays,
  });

  @override
  State<CalendarDays> createState() => CalendarDaysState();
}

class CalendarDaysState extends State<CalendarDays> {
  // Two years either side of today is more than anyone pages through.
  static final _base = _dayOf(
    DateTime.now(),
  ).subtract(const Duration(days: 730));
  static const _count = 1461;

  late final PageController _pages = PageController(
    initialPage: _indexOf(widget.start),
    viewportFraction: 1 / widget.columns,
  );

  int _indexOf(DateTime d) =>
      _dayOf(d).difference(_base).inDays.clamp(0, _count - 1);

  DateTime _dateAt(int i) => DateTime(_base.year, _base.month, _base.day + i);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The first visible day, as the scroll position has it right now.
  DateTime get firstDay => _dateAt(
    (_pages.hasClients ? _pages.page ?? _pages.initialPage : _pages.initialPage)
        .round(),
  );

  void _report() {
    if (!mounted) return;
    final first = firstDay;
    widget.onVisibleDays(
      first,
      DateTime(first.year, first.month, first.day + widget.columns),
    );
  }

  void animateTo(DateTime day) => _pages.animateToPage(
    _indexOf(day),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  /// Moves by [days] days (a week at a time for the arrows of the week view).
  void shift(int days) => animateTo(firstDay.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final byDay = <DateTime, List<TaskEvent>>{};
    for (final e in widget.events) {
      byDay.putIfAbsent(_dayOf(e.start), () => []).add(e);
    }
    for (final list in byDay.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    final today = _dayOf(DateTime.now());

    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _report();
        return false;
      },
      child: PageView.builder(
        controller: _pages,
        pageSnapping: widget.columns == 1,
        padEnds: false,
        itemCount: _count,
        itemBuilder: (context, i) {
          final day = _dateAt(i);
          return _DayColumn(
            day: day,
            isToday: day == today,
            events: byDay[day] ?? const [],
            detailed: widget.columns == 1,
            onTap: widget.onTap,
            onLongPressEvent: widget.onLongPressEvent,
            onLongPressDay: widget.onLongPressDay,
          );
        },
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final List<TaskEvent> events;
  final bool detailed;
  final ValueChanged<TaskEvent> onTap;
  final ValueChanged<TaskEvent> onLongPressEvent;
  final ValueChanged<DateTime> onLongPressDay;

  const _DayColumn({
    required this.day,
    required this.isToday,
    required this.events,
    required this.detailed,
    required this.onTap,
    required this.onLongPressEvent,
    required this.onLongPressDay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final outline = theme.colorScheme.outlineVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => onLongPressDay(day),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: outline)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    DateFormat.E(locale).format(day),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: isToday
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: isToday
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: isToday ? FontWeight.bold : null,
                      ),
                    ),
                  ),
                  if (events.isNotEmpty)
                    Text('${events.length}', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            Divider(height: 1, color: outline),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(3),
                itemCount: events.length,
                itemBuilder: (context, i) => _Chip(
                  event: events[i],
                  detailed: detailed,
                  onTap: onTap,
                  onLongPress: onLongPressEvent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final TaskEvent event;
  final bool detailed;
  final ValueChanged<TaskEvent> onTap;
  final ValueChanged<TaskEvent> onLongPress;

  const _Chip({
    required this.event,
    required this.detailed,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final e = event;
    final foreground = e.color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    final time = TimeOfDay.fromDateTime(e.start).format(context);
    final style = TextStyle(
      fontSize: detailed ? 14 : 11,
      color: foreground,
      decoration: e.task.done ? TextDecoration.lineThrough : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: e.color.withValues(alpha: e.task.done ? 0.45 : 1),
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => onTap(e),
          onLongPress: () => onLongPress(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: style.copyWith(
                    fontSize: (style.fontSize ?? 11) - 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  e.task.title,
                  maxLines: detailed ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
                if (detailed && e.path.isNotEmpty)
                  Text(
                    e.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
