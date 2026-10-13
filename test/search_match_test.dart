import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/core/utils/search_match.dart';

void main() {
  test('folds case and accents', () {
    expect(foldForSearch('Manutenção ÁGUA íóú'), 'manutencao agua iou');
  });

  test('every word, any order, part of a word', () {
    expect(matchesAllWords('Test notification íóú', 'tes not io'), isTrue);
    expect(matchesAllWords('Test notification íóú', 'test iou'), isTrue);
    expect(matchesAllWords('Lavar roupa', 'roupa lavar'), isTrue);
    expect(
      matchesAllWords(
        'Limpar os filtros do ar condicionado',
        'filtro ar condicionado',
      ),
      isTrue,
    );
  });

  test('a missing word fails; an empty query never matches', () {
    expect(matchesAllWords('Test notification', 'test xyz'), isFalse);
    expect(matchesAllWords('Test notification', '   '), isFalse);
  });

  test('task references: id, #index and identifier', () {
    expect(matchesTaskReference(208, 'REP-9', '208'), isTrue);
    expect(matchesTaskReference(208, 'REP-9', '#208'), isTrue);
    expect(matchesTaskReference(208, 'REP-9', '#9'), isTrue);
    expect(matchesTaskReference(208, '#9', '#9'), isTrue);
    expect(matchesTaskReference(208, 'REP-9', 'rep-9'), isTrue);
    expect(matchesTaskReference(208, 'REP-9', ' REP-9 '), isTrue);
    expect(matchesTaskReference(208, 'REP-9', '9'), isFalse);
    expect(matchesTaskReference(208, 'REP-9', 'REP-19'), isFalse);
    expect(matchesTaskReference(208, 'REP-9', 'CASA-9'), isFalse);
    expect(matchesTaskReference(208, 'REP-9', 'abrigo 208'), isFalse);
  });
}
