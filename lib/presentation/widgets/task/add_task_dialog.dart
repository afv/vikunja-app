import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vikunja_app/core/utils/natural_date.dart';
import 'package:vikunja_app/core/theming/app_colors.dart';
import 'package:vikunja_app/core/utils/date_extensions.dart';
import 'package:vikunja_app/core/utils/priority.dart';
import 'package:vikunja_app/domain/entities/new_task_due.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/widgets/date_time_field.dart';

class AddTaskDialog extends StatefulWidget {
  final void Function(
    String title,
    DateTime? dueDate,
    int? projectId,
    int priority,
  )
  onAddTask;
  final String? title;
  final List<Project> projects;
  final int? initialProjectId;

  const AddTaskDialog({
    super.key,
    required this.onAddTask,
    this.title,
    this.projects = const [],
    this.initialProjectId,
  });

  @override
  State<StatefulWidget> createState() => AddTaskDialogState();
}

class AddTaskDialogState extends State<AddTaskDialog> {
  NewTaskDue newTaskDue = NewTaskDue.none;
  DateTime? dueDate;
  var textController = TextEditingController();
  int? selectedProjectId;
  int priority = 0;

  /// Date phrases (`NaturalDateMatch.key`) the user chose to keep as part of the title.
  final List<String> _ignoredPhrases = [];

  /// The user picked a due option or date in this dialog: it wins over a date typed in the title.
  bool _dueExplicit = false;

  @override
  void initState() {
    super.initState();

    var title = widget.title;
    if (title != null) {
      textController.text = _capitalizeFirst(title);
    }
    textController.addListener(_onTitleChanged);
    selectedProjectId = widget.initialProjectId;
  }

  @override
  void dispose() {
    textController.removeListener(_onTitleChanged);
    textController.dispose();
    super.dispose();
  }

  void _onTitleChanged() {
    setState(() {});
  }

  /// `15/10` is read day first on a device whose locale writes the day before the month.
  bool _dayFirst() {
    try {
      final pattern =
          DateFormat.yMd(Localizations.localeOf(context).toString()).pattern ??
          '';
      final day = pattern.indexOf('d');
      final month = pattern.indexOf('M');
      return day == -1 || month == -1 ? true : day < month;
    } catch (_) {
      return true;
    }
  }

  /// The title as typed, read for a date phrase («amanhã às 12»). The time of a phrase that names only a day is the
  /// same nearest hour the due-date chips use.
  NaturalDateResult _parse({bool ignoring = true}) {
    final now = DateTime.now();
    return parseNaturalDate(
      textController.text,
      now,
      defaultTime: DefaultTime(NewTaskDue.none.calculateNearestHours(now), 0),
      dayFirst: _dayFirst(),
      ignore: ignoring ? _ignoredPhrases : const [],
    );
  }

  String _formatDue(NaturalDateMatch match) {
    final locale = Localizations.localeOf(context).toString();
    try {
      final day = DateFormat.MMMEd(locale).format(match.date);
      return match.hasTime
          ? '$day, ${DateFormat.Hm(locale).format(match.date)}'
          : day;
    } catch (_) {
      return match.hasTime
          ? match.date.formatShort()
          : DateFormat.yMMMd().format(match.date);
    }
  }

  /// Under the title: the date the typed words will become (tap to keep them as text), or, once kept, a muted chip
  /// to read them as a date again.
  Widget _phraseChip(AppLocalizations l10n) {
    final match = _parse().match;
    if (match != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InputChip(
            key: const Key('natural-date-chip'),
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.event, size: 18),
            label: Text(
              '${l10n.dueChipLabel(_formatDue(match))}  «${match.text}»',
              overflow: TextOverflow.ellipsis,
            ),
            tooltip: l10n.keepAsTextFor(match.text),
            deleteIcon: const Icon(Icons.close, size: 16),
            deleteButtonTooltipMessage: l10n.keepAsText,
            onPressed: () => setState(() => _ignoredPhrases.add(match.key)),
            onDeleted: () => setState(() => _ignoredPhrases.add(match.key)),
          ),
        ),
      );
    }
    if (_ignoredPhrases.isEmpty) {
      return const SizedBox.shrink();
    }
    final kept = _parse(ignoring: false).match;
    if (kept == null || !_ignoredPhrases.contains(kept.key)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          key: const Key('natural-date-kept-chip'),
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.event_busy, size: 18),
          label: Text(
            l10n.phraseKeptAsText(kept.text),
            overflow: TextOverflow.ellipsis,
          ),
          tooltip: l10n.useAsDateFor(kept.text),
          onPressed: () => setState(() => _ignoredPhrases.remove(kept.key)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var dateTime = DateTime.now();
    final l10n = AppLocalizations.of(context);

    final remainingHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        MediaQuery.paddingOf(context).vertical;
    final maxContentHeight = (remainingHeight - 96).clamp(
      120.0,
      remainingHeight * 0.75,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentHeight),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLines: 1,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.newTaskName,
                  hintText: l10n.newTaskExample,
                ),
                controller: textController,
              ),
              _phraseChip(l10n),
              if (widget.projects.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: DropdownButtonFormField<int>(
                    value: selectedProjectId,
                    isExpanded: true,
                    isDense: true,
                    decoration: InputDecoration(
                      isDense: true,
                      icon: const Icon(Icons.inbox_outlined),
                      labelText: l10n.project,
                      border: InputBorder.none,
                    ),
                    items: widget.projects
                        .map(
                          (project) => DropdownMenuItem(
                            value: project.id,
                            child: Text(
                              project.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedProjectId = value;
                      });
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
                child: Text(l10n.dueDate),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  taskDueList(l10n.dueOptionNone, NewTaskDue.none),
                  if (dateTime.hour < 21)
                    taskDueList(l10n.dueOptionToday, NewTaskDue.today),
                  taskDueList(l10n.dueOptionTomorrow, NewTaskDue.tomorrow),
                  taskDueList(l10n.dueOptionNextMonday, NewTaskDue.nextMonday),
                  if (dateTime.weekday != DateTime.sunday || dateTime.hour < 21)
                    taskDueList(l10n.dueOptionThisWeekend, NewTaskDue.weekend),
                  taskDueList(
                    l10n.dueOptionLaterThisWeek,
                    NewTaskDue.laterThisWeek,
                  ),
                  taskDueList(l10n.dueInOneWeek, NewTaskDue.nextWeek),
                  taskDueList(l10n.dueOptionCustom, NewTaskDue.custom),
                ],
              ),
              if (newTaskDue == NewTaskDue.custom)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: VikunjaDateTimeField(
                    label: l10n.enterExactTime,
                    onChanged: (value) {
                      setState(() => newTaskDue = NewTaskDue.custom);
                      dueDate = value;
                      _dueExplicit = true;
                    },
                  ),
                ),
              if (newTaskDue != NewTaskDue.custom && dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Row(
                    children: [
                      Icon(Icons.date_range, size: 20),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          dueDate!.formatShort(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: DropdownButtonFormField<int>(
                  value: priority,
                  isExpanded: true,
                  isDense: true,
                  decoration: InputDecoration(
                    isDense: true,
                    icon: Icon(
                      key: ValueKey('priority-icon-$priority'),
                      priority == 0 ? Icons.flag_outlined : Icons.flag,
                      color: _priorityColor(context, priority),
                    ),
                    labelText: l10n.priority,
                    border: InputBorder.none,
                  ),
                  selectedItemBuilder: (context) => List.generate(
                    6,
                    (value) => Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        priorityToString(l10n, value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  items: List.generate(
                    6,
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Row(
                        children: [
                          Icon(
                            value == 0 ? Icons.flag_outlined : Icons.flag,
                            size: 20,
                            color: _priorityColor(context, value),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(priorityToString(l10n, value))),
                        ],
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      priority = value ?? 0;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: Text(l10n.cancel),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          onPressed: _normalizedTitle.isEmpty
              ? null
              : () {
                  // an explicit due date wins over one typed in the title, which is cut out of the title either way
                  widget.onAddTask(
                    _normalizedTitle,
                    _dueExplicit ? dueDate : (_parse().match?.date ?? dueDate),
                    selectedProjectId,
                    priority,
                  );
                  Navigator.pop(context);
                },
          child: Text(l10n.add),
        ),
      ],
    );
  }

  String get _normalizedTitle {
    return _capitalizeFirst(_parse().title.trim());
  }

  String _capitalizeFirst(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }

  Widget taskDueList(String name, NewTaskDue thisNewTaskDue) {
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.zero,
      label: Text(name),
      selected: newTaskDue == thisNewTaskDue,
      onSelected: (value) {
        newTaskDue = thisNewTaskDue;
        _dueExplicit = true;
        setState(() {
          if (newTaskDue == NewTaskDue.custom ||
              newTaskDue == NewTaskDue.none) {
            dueDate = null;
          } else {
            dueDate = newTaskDue.calculateDate(DateTime.now());
          }
        });
      },
    );
  }

  Color _priorityColor(BuildContext context, int value) {
    final theme = Theme.of(context);
    final appColors = theme.extension<AppColors>();
    final warning = appColors?.warning ?? Colors.orange;
    final danger = appColors?.danger ?? Colors.red;

    return switch (value) {
      1 => appColors?.success ?? Colors.green,
      2 => warning,
      3 => danger,
      4 => danger,
      5 => danger,
      _ => theme.colorScheme.onSurfaceVariant,
    };
  }
}
