import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/core/utils/natural_date.dart';

// test/natural_date_vectors.json is a copy of vectors.json of the web client (frontend/src/modules/quickAddMagic/
// naturalDate). Both ports are tested against the same cases: keep the files identical.

DateTime local(String value) {
  final [date, time] = value.split('T');
  final [y, m, d] = date.split('-').map(int.parse).toList();
  final [h, min] = time.split(':').map(int.parse).toList();
  return DateTime(y, m, d, h, min);
}

String formatLocal(DateTime date) {
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}T${pad(date.hour)}:${pad(date.minute)}';
}

// Dart has no String.normalize: the one decomposed input in the vectors is composed by the parser itself
String nfc(String text) => text.replaceAll('ã', 'ã');

void main() {
  final vectors =
      jsonDecode(File('test/natural_date_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final [defaultHours, defaultMinutes] = (vectors['defaultTime'] as String)
      .split(':')
      .map(int.parse)
      .toList();
  final options = DefaultTime(defaultHours, defaultMinutes);

  group('parseNaturalDate vectors (shared with the web client)', () {
    for (final raw in vectors['cases'] as List<dynamic>) {
      final vector = raw as Map<String, dynamic>;
      final now = vector['now'] as String?;
      final dayFirst = vector['dayFirst'] as bool?;
      final label =
          '${vector['input']} → ${vector['date'] ?? 'text'}'
          '${now != null ? ' (now $now)' : ''}${dayFirst == false ? ' (month first)' : ''}';
      test(label, () {
        final result = parseNaturalDate(
          vector['input'] as String,
          local(now ?? vectors['now'] as String),
          defaultTime: options,
          dayFirst: dayFirst ?? vectors['dayFirst'] as bool,
          ignore: ((vector['ignore'] as List<dynamic>?) ?? const [])
              .cast<String>(),
        );
        expect(result.title, nfc(vector['title'] as String));
        final date = vector['date'] as String?;
        if (date == null) {
          expect(result.match, isNull);
          return;
        }
        expect(result.match, isNotNull);
        expect(formatLocal(result.match!.date), date);
        expect(result.match!.hasTime, vector['hasTime']);
        if (vector['text'] != null) {
          expect(result.match!.text, vector['text']);
        }
      });
    }
  });

  group('parseNaturalDate match', () {
    final now = local(vectors['now'] as String);
    const defaults = DefaultTime(9, 0);

    test('reports where the phrase sits and a key to remember it by', () {
      const text = 'Comprar pão AMANHÃ às 12';
      final match = parseNaturalDate(text, now, defaultTime: defaults).match!;
      expect(text.substring(match.start, match.end), 'AMANHÃ às 12');
      expect(match.text, 'AMANHÃ às 12');
      expect(match.key, 'amanha as 12');
    });

    test('keeps a phrase as text when its key is ignored', () {
      const text = 'ver 3/4 amanhã';
      final first = parseNaturalDate(text, now, defaultTime: defaults);
      expect(first.match?.key, 'amanha');
      final second = parseNaturalDate(
        text,
        now,
        defaultTime: defaults,
        ignore: [first.match!.key],
      );
      expect(second.match, isNull);
      expect(second.skipped, isTrue);
      expect(second.title, text);
    });

    test('does not change the clock of the caller', () {
      final before = now.millisecondsSinceEpoch;
      parseNaturalDate('amanhã às 12', now, defaultTime: defaults);
      expect(now.millisecondsSinceEpoch, before);
    });

    test('defaults to day first when told nothing', () {
      final match = parseNaturalDate(
        'trip 3/4',
        now,
        defaultTime: defaults,
      ).match!;
      expect(formatLocal(match.date), '2027-04-03T09:00');
    });

    test('uses the default time for a day without one', () {
      final match = parseNaturalDate(
        'trip amanhã',
        now,
        defaultTime: const DefaultTime(14, 30),
      ).match!;
      expect(formatLocal(match.date), '2026-10-15T14:30');
      expect(match.hasTime, isFalse);
    });

    test('is not skipped when nothing was ignored', () {
      expect(
        parseNaturalDate('buy milk', now, defaultTime: defaults).skipped,
        isFalse,
      );
    });
  });
}
