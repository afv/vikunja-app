import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:vikunja_app/core/utils/task_list_html.dart';

const _list =
    '<p>Intro</p><ul data-type="taskList">'
    '<li data-checked="false" data-type="taskItem"><label><input type="checkbox"><span></span></label><div><p>Zamioculcas → sala</p></div></li>'
    '<li data-checked="true" data-type="taskItem"><label><input type="checkbox" checked="checked"><span></span></label><div><p>Aloé <strong>vera</strong></p></div></li>'
    '</ul>';

void main() {
  test('finds the items, their state, position and content', () {
    final items = html_parser
        .parseFragment(_list)
        .querySelectorAll('li[data-type="taskItem"]');
    expect(items.map(isTaskItem), [true, true]);
    expect(items.map(isTaskItemChecked), [false, true]);
    expect(items.map(taskItemIndex), [0, 1]);
    expect(taskItemContentHtml(items[1]), '<p>Aloé <strong>vera</strong></p>');
  });

  test('ticks and unticks one item, leaving the rest as it was', () {
    final ticked = setTaskItemChecked(_list, 0, true);
    final items = html_parser
        .parseFragment(ticked)
        .querySelectorAll('li[data-type="taskItem"]');
    expect(items.map(isTaskItemChecked), [true, true]);
    expect(items[0].querySelector('input')!.attributes['checked'], 'checked');
    expect(ticked, startsWith('<p>Intro</p>'));

    final unticked = setTaskItemChecked(ticked, 1, false);
    final again = html_parser
        .parseFragment(unticked)
        .querySelectorAll('li[data-type="taskItem"]');
    expect(again.map(isTaskItemChecked), [true, false]);
    expect(
      again[1].querySelector('input')!.attributes.containsKey('checked'),
      isFalse,
    );
  });

  test('an index out of range changes nothing', () {
    expect(setTaskItemChecked(_list, 5, true), _list);
    expect(setTaskItemChecked('<p>no list</p>', 0, true), '<p>no list</p>');
  });
}
