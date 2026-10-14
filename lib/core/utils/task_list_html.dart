/// Checkbox lists in task descriptions, as the web editor (TipTap) writes them:
/// `<ul data-type="taskList"><li data-type="taskItem" data-checked="false"><label><input type="checkbox">…</label><div>…</div></li></ul>`.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

const _itemSelector = 'li[data-type="taskItem"]';

bool isTaskItem(dom.Element element) =>
    element.localName == 'li' && element.attributes['data-type'] == 'taskItem';

bool isTaskItemChecked(dom.Element element) =>
    element.attributes['data-checked'] == 'true';

/// Position of [item] among all checkbox items of its document, or -1.
int taskItemIndex(dom.Element item) {
  dom.Node root = item;
  while (root.parentNode != null) {
    root = root.parentNode!;
  }
  final List<dom.Element> items;
  if (root is dom.Document) {
    items = root.querySelectorAll(_itemSelector);
  } else if (root is dom.DocumentFragment) {
    items = root.querySelectorAll(_itemSelector);
  } else {
    return -1;
  }
  return items.indexOf(item);
}

/// The item's content without its checkbox, as HTML.
String taskItemContentHtml(dom.Element item) {
  final div = item.children.where((c) => c.localName == 'div').toList();
  if (div.isNotEmpty) return div.first.innerHtml;
  final clone = item.clone(true);
  clone.querySelectorAll('label, input').forEach((e) => e.remove());
  return clone.innerHtml;
}

/// (ticked, total) checkbox items in [description].
(int, int) countTaskItems(String description) {
  final items = html_parser
      .parseFragment(description)
      .querySelectorAll(_itemSelector);
  return (items.where(isTaskItemChecked).length, items.length);
}

/// [description] with checkbox item number [index] set to [checked]; unchanged if there is no such item.
String setTaskItemChecked(String description, int index, bool checked) {
  final fragment = html_parser.parseFragment(description);
  final items = fragment.querySelectorAll(_itemSelector);
  if (index < 0 || index >= items.length) return description;
  final item = items[index];
  item.attributes['data-checked'] = checked ? 'true' : 'false';
  for (final input in item.querySelectorAll('input[type="checkbox"]')) {
    if (checked) {
      input.attributes['checked'] = 'checked';
    } else {
      input.attributes.remove('checked');
    }
  }
  return fragment.outerHtml;
}
