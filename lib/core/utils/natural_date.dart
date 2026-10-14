/// Finds a date phrase in English or Portuguese in a task title: «pay rent next friday at 5pm»,
/// «ligar ao João amanhã às 12».
///
/// This is a port of the web client's `naturalDate.ts` (vikunja frontend, modules/quickAddMagic/naturalDate, with its
/// SPEC.md): the same pieces, vocabulary and rules. Both are tested against one file of cases,
/// `test/natural_date_vectors.json` here and `vectors.json` there. Keep the two implementations in step.
///
/// Differences from the TypeScript: none in behaviour. Unicode composition (NFC) is limited to the combining
/// marks of Portuguese and English text (acute, grave, circumflex, tilde, diaeresis, cedilla on the usual letters).
library;

/// The time of a phrase that names only a day.
class DefaultTime {
  final int hours;
  final int minutes;

  const DefaultTime(this.hours, this.minutes);
}

class NaturalDateMatch {
  /// The phrase as typed, with its leading connector.
  final String text;
  final int start;
  final int end;
  final DateTime date;
  final bool hasTime;

  /// Folded, whitespace-collapsed phrase: what «keep it as text» remembers.
  final String key;

  const NaturalDateMatch({
    required this.text,
    required this.start,
    required this.end,
    required this.date,
    required this.hasTime,
    required this.key,
  });
}

class NaturalDateResult {
  final String title;
  final NaturalDateMatch? match;

  /// A phrase was found but the user chose to keep it as text.
  final bool skipped;

  const NaturalDateResult(this.title, this.match, {this.skipped = false});
}

class _Ymd {
  final int y;

  /// 0-based, like JavaScript's months: the algorithm is shared with the web client.
  final int m;
  final int d;

  const _Ymd(this.y, this.m, this.d);
}

class _Clock {
  final int h;
  final int m;

  const _Clock(this.h, this.m);
}

abstract class _Piece {
  final int start;
  final int end;
  final bool strong;

  const _Piece(this.start, this.end, this.strong);
}

class _DayPiece extends _Piece {
  final _Ymd ymd;
  final _Clock? implied;

  const _DayPiece(
    super.start,
    super.end,
    super.strong,
    this.ymd, [
    this.implied,
  ]);
}

class _TimePiece extends _Piece {
  final _Clock clock;

  /// The hour was said with am/pm or «da tarde», so a period of the day may not shift it.
  final bool exact;

  const _TimePiece(
    super.start,
    super.end,
    super.strong,
    this.clock,
    this.exact,
  );
}

class _InstantPiece extends _Piece {
  final DateTime date;

  const _InstantPiece(int start, int end, this.date) : super(start, end, true);
}

// ------------------------------------------------------------------------------------------------ vocabulary

const _weekdays = <String, int>{
  'monday': 1,
  'tuesday': 2,
  'wednesday': 3,
  'thursday': 4,
  'friday': 5,
  'saturday': 6,
  'sunday': 7,
  'mon': 1,
  'tue': 2,
  'tues': 2,
  'wed': 3,
  'thu': 4,
  'thur': 4,
  'thurs': 4,
  'fri': 5,
  'sat': 6,
  'sun': 7,
  'segunda': 1,
  'terca': 2,
  'quarta': 3,
  'quinta': 4,
  'sexta': 5,
  'sabado': 6,
  'domingo': 7,
};
const _fullWeekdays =
    'monday|tuesday|wednesday|thursday|friday|saturday|sunday'
    '|segunda(?:[- ]feira)?|terca(?:[- ]feira)?|quarta(?:[- ]feira)?|quinta(?:[- ]feira)?|sexta(?:[- ]feira)?|sabado|domingo';
const _abbreviatedWeekdays = 'mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun';

const _months = <String, int>{
  'january': 0,
  'february': 1,
  'march': 2,
  'april': 3,
  'may': 4,
  'june': 5,
  'july': 6,
  'august': 7,
  'september': 8,
  'october': 9,
  'november': 10,
  'december': 11,
  'jan': 0,
  'feb': 1,
  'mar': 2,
  'apr': 3,
  'jun': 5,
  'jul': 6,
  'aug': 7,
  'sep': 8,
  'sept': 8,
  'oct': 9,
  'nov': 10,
  'dec': 11,
  'janeiro': 0,
  'fevereiro': 1,
  'marco': 2,
  'abril': 3,
  'maio': 4,
  'junho': 5,
  'julho': 6,
  'agosto': 7,
  'setembro': 8,
  'outubro': 9,
  'novembro': 10,
  'dezembro': 11,
  'fev': 1,
  'abr': 3,
  'mai': 4,
  'ago': 7,
  'set': 8,
  'out': 9,
  'dez': 11,
};

String _byLength(Iterable<String> words) =>
    (words.toList()..sort((a, b) => b.length.compareTo(a.length))).join('|');

final _monthNames = _byLength(_months.keys);
// short forms that are also ordinary words: a month only with «de»/«of», or spelled out
const _ambiguousMonths = {'mar', 'set', 'out'};

const _numberWords = <String, int>{
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'um': 1,
  'uma': 1,
  'dois': 2,
  'duas': 2,
  'tres': 3,
  'quatro': 4,
  'cinco': 5,
  'seis': 6,
  'sete': 7,
  'oito': 8,
  'nove': 9,
  'dez': 10,
  'onze': 11,
  'doze': 12,
};
final _numberWordAlternation = _byLength(_numberWords.keys);

const _units = <String, String>{
  'minute': 'minute',
  'minutes': 'minute',
  'min': 'minute',
  'mins': 'minute',
  'minuto': 'minute',
  'minutos': 'minute',
  'hour': 'hour',
  'hours': 'hour',
  'hr': 'hour',
  'hrs': 'hour',
  'hora': 'hour',
  'horas': 'hour',
  'day': 'day',
  'days': 'day',
  'dia': 'day',
  'dias': 'day',
  'week': 'week',
  'weeks': 'week',
  'semana': 'week',
  'semanas': 'week',
  'month': 'month',
  'months': 'month',
  'mes': 'month',
  'meses': 'month',
  'year': 'year',
  'years': 'year',
  'ano': 'year',
  'anos': 'year',
};
final _unitAlternation = _byLength(_units.keys);

const _periodTimes = <String, _Clock>{
  'morning': _Clock(9, 0),
  'de manha': _Clock(9, 0),
  'afternoon': _Clock(15, 0),
  'a tarde': _Clock(15, 0),
  'evening': _Clock(19, 0),
  'night': _Clock(21, 0),
  'a noite': _Clock(21, 0),
};

// ------------------------------------------------------------------------------------------------ text helpers

// the lowercase letters that Unicode decomposes into a base letter and a combining mark, and those base letters
const _accented =
    'àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżžơưǎǐǒǔǖǘǚǜǟǡǣǧǩǫǭǯǰǵǹǻǽǿȁȃȅȇȉȋȍȏȑȓȕȗșțȟȧȩȫȭȯȱȳ';
const _bases =
    'aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzzouaiouuuuuaaægkooʒjgnaæøaaeeiioorruusthaeooooy';

final _foldMap = () {
  assert(_accented.length == _bases.length, 'accent table out of step');
  return {for (var i = 0; i < _accented.length; i++) _accented[i]: _bases[i]};
}();

/// Lowercase and without accents, one character for one character, so positions stay valid in the original.
String _fold(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    out.write(lower.length == char.length ? (_foldMap[lower] ?? lower) : char);
  }
  return out.toString();
}

const _composed = <String, String>{
  'á': 'á',
  'é': 'é',
  'í': 'í',
  'ó': 'ó',
  'ú': 'ú',
  'ý': 'ý',
  'Á': 'Á',
  'É': 'É',
  'Í': 'Í',
  'Ó': 'Ó',
  'Ú': 'Ú',
  'Ý': 'Ý',
  'à': 'à',
  'è': 'è',
  'ì': 'ì',
  'ò': 'ò',
  'ù': 'ù',
  'À': 'À',
  'È': 'È',
  'Ì': 'Ì',
  'Ò': 'Ò',
  'Ù': 'Ù',
  'â': 'â',
  'ê': 'ê',
  'î': 'î',
  'ô': 'ô',
  'û': 'û',
  'Â': 'Â',
  'Ê': 'Ê',
  'Î': 'Î',
  'Ô': 'Ô',
  'Û': 'Û',
  'ã': 'ã',
  'õ': 'õ',
  'ñ': 'ñ',
  'Ã': 'Ã',
  'Õ': 'Õ',
  'Ñ': 'Ñ',
  'ä': 'ä',
  'ë': 'ë',
  'ï': 'ï',
  'ö': 'ö',
  'ü': 'ü',
  'ÿ': 'ÿ',
  'Ä': 'Ä',
  'Ë': 'Ë',
  'Ï': 'Ï',
  'Ö': 'Ö',
  'Ü': 'Ü',
  'ç': 'ç',
  'Ç': 'Ç',
};

/// NFC for the combining marks that Portuguese and English text uses; anything else is left as it is.
String _compose(String text) => text.replaceAllMapped(
  RegExp('[A-Za-z][̀-̧̈]'),
  (m) => _composed[m[0]!] ?? m[0]!,
);

int _daysInMonth(int y, int m) => DateTime(y, m + 2, 0).day;

_Ymd _addDays(_Ymd ymd, int days) {
  final date = DateTime(ymd.y, ymd.m + 1, ymd.d + days);
  return _Ymd(date.year, date.month - 1, date.day);
}

_Ymd _addMonths(_Ymd ymd, int months) {
  final target = DateTime(ymd.y, ymd.m + 1 + months, 1);
  final day = ymd.d < _daysInMonth(target.year, target.month - 1)
      ? ymd.d
      : _daysInMonth(target.year, target.month - 1);
  return _Ymd(target.year, target.month - 1, day);
}

_Ymd _toYmd(DateTime date) => _Ymd(date.year, date.month - 1, date.day);
DateTime _toDate(_Ymd ymd, _Clock clock) =>
    DateTime(ymd.y, ymd.m + 1, ymd.d, clock.h, clock.m);
bool _isValidDay(int y, int m, int d) =>
    m >= 0 && m <= 11 && d >= 1 && d <= _daysInMonth(y, m);

/// The next occurrence of a day/month that has no year: this year, or next year when it has passed.
_Ymd? _resolveYearless(_Ymd today, int m, int d) {
  for (var y = today.y; y <= today.y + 4; y++) {
    if (!_isValidDay(y, m, d)) {
      continue;
    }
    if (!_toDate(
      _Ymd(y, m, d),
      const _Clock(0, 0),
    ).isBefore(_toDate(today, const _Clock(0, 0)))) {
      return _Ymd(y, m, d);
    }
  }
  return null;
}

int _normalizeYear(String year) =>
    year.length == 2 ? 2000 + int.parse(year) : int.parse(year);

// ------------------------------------------------------------------------------------------------ pieces

// no «@» either: «@today» is an assignee called today
const _notBefore = r'(?<![a-z0-9@])';
const _notAfter = r'(?![a-z0-9])';
const _deadlineLead = r'(?:(?:by|until|due(?: on| by)?|before|ate|para)\s+)?';

int _weekdayOf(String token) =>
    _weekdays[token.replaceFirst(RegExp(r'[- ]feira$'), '')]!;

List<_Piece> _findDayWords(String text, _Ymd today) {
  final pieces = <_Piece>[];
  final regex = RegExp(
    '$_notBefore(?<lead>$_deadlineLead)(?<word>day after tomorrow|depois de amanha|tomorrow|tmrw|amanha|today|hoje|tonight|esta noite)'
    r'(?:\s+(?<period>de manha|a tarde|a noite|morning|afternoon|evening|night))?'
    '$_notAfter',
  );
  const offsets = {
    'today': 0,
    'hoje': 0,
    'tonight': 0,
    'esta noite': 0,
    'tomorrow': 1,
    'tmrw': 1,
    'amanha': 1,
    'day after tomorrow': 2,
    'depois de amanha': 2,
  };
  for (final found in regex.allMatches(text)) {
    final word = found.namedGroup('word')!;
    final period = found.namedGroup('period');
    _Clock? implied;
    if (word == 'tonight' || word == 'esta noite') {
      implied = const _Clock(21, 0);
    } else if (period != null) {
      implied = _periodTimes[period];
    }
    pieces.add(
      _DayPiece(
        found.start,
        found.end,
        true,
        _addDays(today, offsets[word]!),
        implied,
      ),
    );
  }
  return pieces;
}

List<_Piece> _findWeekdays(String text, DateTime now) {
  final pieces = <_Piece>[];
  final regex = RegExp(
    '$_notBefore(?<lead>$_deadlineLead)(?:(?<mod>next|this|coming|proxim[ao]|est[ae]|on|n[ao]|em)\\s+)?'
    '(?<wd>$_fullWeekdays|$_abbreviatedWeekdays)$_notAfter',
  );
  final today = _toYmd(now);
  final dow = now.weekday;
  for (final found in regex.allMatches(text)) {
    final mod = found.namedGroup('mod');
    // the next such day, today when it is one: «next» and «this» change nothing, as in the older parser
    final ahead = (_weekdayOf(found.namedGroup('wd')!) - dow + 7) % 7;
    pieces.add(
      _DayPiece(found.start, found.end, mod != null, _addDays(today, ahead)),
    );
  }
  return pieces;
}

List<_Piece> _findPeriods(String text, DateTime now) {
  final pieces = <_Piece>[];
  final today = _toYmd(now);
  final dow = now.weekday;
  final laterThisWeek = dow >= 5 ? 0 : 2; // Friday, Saturday, Sunday: today
  final phrases = <(String, _Ymd)>[
    (r'(?:na\s+)?(?:next week|proxima semana)', _addDays(today, 7)),
    (r'(?:no\s+)?(?:next month|proximo mes)', _Ymd(today.y, today.m + 1, 1)),
    (
      r'(?:no\s+)?(?:end of (?:the )?month|fim do mes|final do mes)',
      _Ymd(today.y, today.m, _daysInMonth(today.y, today.m)),
    ),
    (
      r'(?:this weekend|(?:neste|este) fim de semana)',
      _addDays(today, dow >= 6 ? 0 : 6 - dow),
    ),
    ('later this week', _addDays(today, laterThisWeek)),
    ('later next week', _addDays(today, laterThisWeek + 7)),
  ];
  for (final (pattern, ymd) in phrases) {
    final regex = RegExp('$_notBefore$_deadlineLead$pattern$_notAfter');
    for (final found in regex.allMatches(text)) {
      final date = DateTime(ymd.y, ymd.m + 1, ymd.d);
      pieces.add(_DayPiece(found.start, found.end, true, _toYmd(date)));
    }
  }
  return pieces;
}

List<_Piece> _findOffsets(String text, DateTime now, _Ymd today) {
  final pieces = <_Piece>[];
  const lead = r'(?:in|em|daqui a|dentro de)';
  final half = RegExp(
    '$_notBefore$lead\\s+(?:half an? hour|meia hora)$_notAfter',
  );
  final counted = RegExp(
    '$_notBefore$lead\\s+(?<n>\\d{1,3}|$_numberWordAlternation)\\s+(?<unit>$_unitAlternation)$_notAfter',
  );

  void instant(RegExpMatch found, int minutes) {
    final moved = now.add(Duration(minutes: minutes));
    pieces.add(
      _InstantPiece(
        found.start,
        found.end,
        DateTime(moved.year, moved.month, moved.day, moved.hour, moved.minute),
      ),
    );
  }

  for (final found in half.allMatches(text)) {
    instant(found, 30);
  }
  for (final found in counted.allMatches(text)) {
    final word = found.namedGroup('n')!;
    final n = RegExp(r'^\d').hasMatch(word)
        ? int.parse(word)
        : _numberWords[word]!;
    final unit = _units[found.namedGroup('unit')!];
    if (unit == 'minute') {
      instant(found, n);
    } else if (unit == 'hour') {
      instant(found, n * 60);
    } else {
      final ymd = switch (unit) {
        'day' => _addDays(today, n),
        'week' => _addDays(today, 7 * n),
        'month' => _addMonths(today, n),
        _ => _addMonths(today, 12 * n),
      };
      pieces.add(_DayPiece(found.start, found.end, true, ymd));
    }
  }
  return pieces;
}

List<_Piece> _findAbsoluteDates(String text, _Ymd today, bool dayFirst) {
  final pieces = <_Piece>[];

  // «pagar renda dia 5», «pay rent on the 1st»: the next day of the month with that number
  final dayOfMonth = RegExp(
    '$_notBefore(?:dia\\s+(?<n1>\\d{1,2})|on the (?<n2>\\d{1,2})(?:st|nd|rd|th))(?![0-9a-z/])',
  );
  for (final found in dayOfMonth.allMatches(text)) {
    final day = int.parse(found.namedGroup('n1') ?? found.namedGroup('n2')!);
    for (var offset = 0; offset < 14; offset++) {
      final month = _addMonths(_Ymd(today.y, today.m, 1), offset);
      if (day < 1 || !_isValidDay(month.y, month.m, day)) {
        continue;
      }
      final ymd = _Ymd(month.y, month.m, day);
      if (!_toDate(
        ymd,
        const _Clock(0, 0),
      ).isBefore(_toDate(today, const _Clock(0, 0)))) {
        pieces.add(_DayPiece(found.start, found.end, true, ymd));
        break;
      }
    }
  }

  const lead = r'(?:(?:on|by|until|due(?: on| by)?|before|ate|para|no|em)\s+)?';

  final iso = RegExp(
    '(?<![0-9])$lead(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})(?![0-9])',
  );
  for (final found in iso.allMatches(text)) {
    final y = int.parse(found.namedGroup('y')!);
    final m = int.parse(found.namedGroup('m')!) - 1;
    final d = int.parse(found.namedGroup('d')!);
    if (_isValidDay(y, m, d)) {
      pieces.add(_DayPiece(found.start, found.end, true, _Ymd(y, m, d)));
    }
  }

  final numeric = RegExp(
    '(?<![0-9/.\\-])$lead(?<a>\\d{1,2})(?<sep>[/.\\-])(?<b>\\d{1,2})(?:\\k<sep>(?<y>\\d{4}|\\d{2}))?(?![0-9a-z/])',
  );
  for (final found in numeric.allMatches(text)) {
    final a = found.namedGroup('a')!;
    final b = found.namedGroup('b')!;
    final sep = found.namedGroup('sep')!;
    final y = found.namedGroup('y');
    // «1.5» and «10-12» are numbers and ranges unless a year makes them a date («01.02» is one: both parts padded)
    if (sep == '-' && (y == null || y.length != 4)) {
      continue;
    }
    if (sep == '.' && y == null && !(a.length == 2 && b.length == 2)) {
      continue;
    }
    final first = int.parse(a);
    final second = int.parse(b);
    // only the slash follows the locale: «15.10.2026» and «15-10-2026» are always day first
    final orders = dayFirst || sep != '/'
        ? [(first, second), (second, first)]
        : [(second, first), (first, second)];
    for (final (day, month) in orders) {
      _Ymd? ymd;
      if (y != null) {
        final year = _normalizeYear(y);
        ymd = _isValidDay(year, month - 1, day)
            ? _Ymd(year, month - 1, day)
            : null;
      } else {
        ymd = month >= 1 && month <= 12
            ? _resolveYearless(today, month - 1, day)
            : null;
      }
      if (ymd != null) {
        pieces.add(_DayPiece(found.start, found.end, false, ymd));
        break;
      }
    }
  }

  const monthLead =
      r'(?:(?:on|by|until|due(?: on| by)?|before|ate|para|em|no|na|a|dia)\s+)?';
  final dayMonth = RegExp(
    '$_notBefore$monthLead(?<d>\\d{1,2})(?:st|nd|rd|th|o|º|°)?\\s+(?:(?<de>de|of)\\s+)?(?<mon>$_monthNames)'
    '(?:\\s+(?:de\\s+)?(?<y>\\d{4}))?$_notAfter',
  );
  final monthDay = RegExp(
    '$_notBefore$monthLead(?<mon>$_monthNames)\\s+(?<d>\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(?<y>\\d{4}))?(?![0-9a-z])',
  );
  for (final (regex, spelled) in [(dayMonth, true), (monthDay, false)]) {
    for (final found in regex.allMatches(text)) {
      final mon = found.namedGroup('mon')!;
      final y = found.namedGroup('y');
      final de = spelled ? found.namedGroup('de') : null;
      if (_ambiguousMonths.contains(mon) && !(spelled && de != null)) {
        continue;
      }
      final month = _months[mon]!;
      final day = int.parse(found.namedGroup('d')!);
      final _Ymd? ymd = y != null
          ? (_isValidDay(int.parse(y), month, day)
                ? _Ymd(int.parse(y), month, day)
                : null)
          : _resolveYearless(today, month, day);
      if (ymd != null) {
        pieces.add(_DayPiece(found.start, found.end, true, ymd));
      }
    }
  }
  return pieces;
}

_Clock? _clockFrom(int h, int m, [String? meridiem, String? part]) {
  if (m < 0 || m > 59) {
    return null;
  }
  if (meridiem != null) {
    if (h < 1 || h > 12) {
      return null;
    }
    return _Clock(meridiem == 'pm' ? (h % 12) + 12 : h % 12, m);
  }
  if (part != null && h <= 12) {
    if (part == 'tarde') {
      return _Clock(h < 12 ? h + 12 : h, m);
    }
    if (part == 'noite') {
      return _Clock(h == 12 ? 0 : (h < 12 ? h + 12 : h), m);
    }
    return _Clock(h == 12 ? 0 : h, m); // manhã, madrugada
  }
  return h > 23 ? null : _Clock(h, m);
}

final _timeRegex = RegExp(
  r'(?<![a-z0-9:])(?:(?<lead>(?:until|by|ate|para)\s+))?(?:(?<pre>at|@|as|ao|pelas|a)\s*)?(?:'
  r'(?<h1>\d{1,2}):(?<m1>\d{2})(?:\s?(?<ap1>am|pm))?'
  r'|(?<h2>\d{1,2})\s?(?:horas?|h(?<m2>\d{2})?)'
  r'|(?<h3>\d{1,2})\s?(?<ap3>am|pm)'
  r'|(?<h4>\d{1,2})(?:\s+(?:horas?\s+)?(?:da\s+(?<part4>manha|tarde|noite|madrugada)|(?<ap4>am|pm)))?(?![0-9:/.\-])'
  r'|(?<word>meio[- ]dia|meia[- ]noite|noon|midday|midnight)'
  r')(?![a-z0-9])',
);

List<_Piece> _findTimes(String text) {
  final pieces = <_Piece>[];
  for (final found in _timeRegex.allMatches(text)) {
    String? g(String name) => found.namedGroup(name);
    final pre = g('pre');
    final strongPre = pre != null && pre != 'a';
    _Clock? clock;
    if (g('h1') != null) {
      clock = _clockFrom(int.parse(g('h1')!), int.parse(g('m1')!), g('ap1'));
    } else if (g('h2') != null) {
      clock = _clockFrom(
        int.parse(g('h2')!),
        g('m2') != null ? int.parse(g('m2')!) : 0,
      );
    } else if (g('h3') != null) {
      clock = _clockFrom(int.parse(g('h3')!), 0, g('ap3'));
    } else if (g('h4') != null) {
      if (!strongPre) {
        continue; // a bare number is a time only after «at», «@», «às»: «a 5 km» is not
      }
      clock = _clockFrom(int.parse(g('h4')!), 0, g('ap4'), g('part4'));
    } else if (g('word') != null) {
      clock = RegExp(r'^(meio|noon|midday)').hasMatch(g('word')!)
          ? const _Clock(12, 0)
          : const _Clock(0, 0);
    }
    if (clock != null) {
      final exact =
          g('ap1') != null ||
          g('ap3') != null ||
          g('ap4') != null ||
          g('part4') != null ||
          clock.h >= 12 ||
          g('word') != null;
      pieces.add(_TimePiece(found.start, found.end, strongPre, clock, exact));
    }
  }
  return pieces;
}

// ------------------------------------------------------------------------------------------------ grouping

bool _overlaps(_Piece a, _Piece b) => a.start < b.end && b.start < a.end;

class _Group {
  int start;
  int end;
  _DayPiece? day;
  _TimePiece? time;
  _InstantPiece? instant;
  bool strong;

  _Group(this.start, this.end, this.strong);
}

// between a day and a time: spaces, a comma, or «de»/«on»…: «às 20h30 de sexta», «friday, at 5»
final _mergeableGap = RegExp(
  r'^[\s,]*(?:(?:de|do|da|on|of|em|no|na)\s+)?[\s,]*$',
);
final _trailingPunctuation = RegExp(r'^[\s.,!?;:]*$');

List<_Group> _groupPieces(String text, List<_Piece> pieces) {
  final indexed = [for (var i = 0; i < pieces.length; i++) (i, pieces[i])]
    ..sort(
      (a, b) => a.$2.start != b.$2.start
          ? a.$2.start.compareTo(b.$2.start)
          : a.$1.compareTo(b.$1),
    );
  final groups = <_Group>[];
  _Group? current;
  for (final (_, piece) in indexed) {
    final mergeable =
        current != null &&
        piece is! _InstantPiece &&
        current.instant == null &&
        (piece is _DayPiece ? current.day == null : current.time == null) &&
        _mergeableGap.hasMatch(text.substring(current.end, piece.start));
    if (current != null && mergeable) {
      current.end = piece.end;
      current.strong = current.strong || piece.strong;
      if (piece is _DayPiece) {
        current.day = piece;
      } else if (piece is _TimePiece) {
        current.time = piece;
      }
      continue;
    }
    current = _Group(piece.start, piece.end, piece.strong);
    if (piece is _DayPiece) {
      current.day = piece;
    } else if (piece is _TimePiece) {
      current.time = piece;
    } else if (piece is _InstantPiece) {
      current.instant = piece;
    }
    groups.add(current);
  }
  return groups;
}

(DateTime, bool) _resolveGroup(
  _Group group,
  DateTime now,
  DefaultTime defaultTime,
) {
  if (group.instant != null) {
    return (group.instant!.date, true);
  }
  final day = group.day;
  if (day != null) {
    var clock =
        group.time?.clock ??
        day.implied ??
        _Clock(defaultTime.hours, defaultTime.minutes);
    // «at 8 tonight», «amanhã à tarde às 5»: an hour said without am/pm follows the period of the day
    final time = group.time;
    if (time != null &&
        !time.exact &&
        day.implied != null &&
        day.implied!.h >= 15 &&
        clock.h < 12) {
      clock = _Clock(clock.h + 12, clock.m);
    }
    return (_toDate(day.ymd, clock), time != null || day.implied != null);
  }
  final clock = group.time!.clock;
  var date = _toDate(_toYmd(now), clock);
  if (date.isBefore(now)) {
    date = _toDate(_addDays(_toYmd(now), 1), clock);
  }
  return (date, true);
}

/// Cuts a span out without tidying, so positions before it stay valid.
String _cut(String text, int start, int end) {
  final before = text.substring(0, start);
  final after = text.substring(end);
  // «buy bread tomorrow!» keeps its «!» attached to the word before it; otherwise one space is left, not two
  if (RegExp(r'^\s*[.,;:!?)]').hasMatch(after)) {
    return before.trimRight() + after.trimLeft();
  }
  return before.trimRight().isEmpty || after.trimLeft().isEmpty
      ? before + after
      : '${before.trimRight()} ${after.trimLeft()}';
}

String _tidy(String text) =>
    text.trim().replaceAll(RegExp(r'^[,;:\s]+|[,;:\s]+$'), '');

// ------------------------------------------------------------------------------------------------ entry point

class _Candidate {
  final _Group group;
  final String key;
  final String text;

  _Candidate(this.group, this.key, this.text);
}

/// The last date phrase in [input], resolved against [now], and the title without it. See SPEC.md of the web
/// client for the grammar. [ignore] holds the keys of phrases the user chose to keep as text.
NaturalDateResult parseNaturalDate(
  String input,
  DateTime now, {
  required DefaultTime defaultTime,
  bool dayFirst = true,
  List<String> ignore = const [],
}) {
  final text = _compose(input);
  final none = NaturalDateResult(text, null);
  if (text.trim().isEmpty) {
    return none;
  }

  final folded = _fold(text);
  final today = _toYmd(now);
  final ignored = ignore.toSet();

  // most specific first: a later piece that overlaps an earlier one is dropped
  final found = [
    ..._findOffsets(folded, now, today),
    ..._findAbsoluteDates(folded, today, dayFirst),
    ..._findPeriods(folded, now),
    ..._findWeekdays(folded, now),
    ..._findDayWords(folded, today),
    ..._findTimes(folded),
  ];
  // the longest phrase wins where two overlap («dia 20 de dezembro» over «dia 20»); a stable sort, like the original
  final ranked = [for (var i = 0; i < found.length; i++) (i, found[i])]
    ..sort((a, b) {
      final byLength = (b.$2.end - b.$2.start).compareTo(a.$2.end - a.$2.start);
      if (byLength != 0) {
        return byLength;
      }
      return a.$2.start != b.$2.start
          ? a.$2.start.compareTo(b.$2.start)
          : a.$1.compareTo(b.$1);
    });
  final pieces = <_Piece>[];
  for (final (_, candidate) in ranked) {
    if (!pieces.any((kept) => _overlaps(kept, candidate))) {
      pieces.add(candidate);
    }
  }

  // a phrase that is only a day or only a time sitting alone in the middle of the text is not a phrase
  final candidates = [
    for (final group in _groupPieces(folded, pieces))
      if (group.strong ||
          folded.substring(0, group.start).trim().isEmpty ||
          _trailingPunctuation.hasMatch(folded.substring(group.end)))
        _Candidate(
          group,
          folded
              .substring(group.start, group.end)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim(),
          text.substring(group.start, group.end),
        ),
  ];

  final skipped = <_Group>{};
  var sawIgnored = false;
  for (var i = candidates.length - 1; i >= 0; i--) {
    final last = candidates[i];
    if (skipped.contains(last.group)) {
      continue;
    }
    // «Segunda reunião às 10h»: the last phrase gives only a time (or only a day) and an earlier one gives the other
    final needsDay = last.group.day == null && last.group.instant == null;
    final needsTime = last.group.time == null && last.group.instant == null;
    _Candidate? partner;
    if (needsDay || needsTime) {
      for (var j = i - 1; j >= 0; j--) {
        final other = candidates[j];
        if (!skipped.contains(other.group) &&
            other.group.instant == null &&
            ((needsDay &&
                    other.group.day != null &&
                    other.group.time == null) ||
                (needsTime &&
                    other.group.time != null &&
                    other.group.day == null))) {
          partner = other;
          break;
        }
      }
    }

    if (partner != null) {
      final key = '${partner.key} + ${last.key}';
      if (ignored.contains(key)) {
        skipped.add(last.group);
        skipped.add(partner.group);
        sawIgnored = true;
        continue;
      }
      final title = _tidy(
        _cut(
          _cut(text, last.group.start, last.group.end),
          partner.group.start,
          partner.group.end,
        ),
      );
      if (title.isNotEmpty) {
        final merged = _Group(partner.group.start, last.group.end, true)
          ..day = last.group.day ?? partner.group.day
          ..time = last.group.time ?? partner.group.time;
        final (date, hasTime) = _resolveGroup(merged, now, defaultTime);
        return NaturalDateResult(
          title,
          NaturalDateMatch(
            text: '${partner.text} … ${last.text}',
            start: merged.start,
            end: merged.end,
            date: date,
            hasTime: hasTime,
            key: key,
          ),
        );
      }
    }

    if (ignored.contains(last.key)) {
      sawIgnored = true;
      continue;
    }
    final title = _tidy(_cut(text, last.group.start, last.group.end));
    if (title.isEmpty) {
      continue;
    }
    final (date, hasTime) = _resolveGroup(last.group, now, defaultTime);
    return NaturalDateResult(
      title,
      NaturalDateMatch(
        text: last.text,
        start: last.group.start,
        end: last.group.end,
        date: date,
        hasTime: hasTime,
        key: last.key,
      ),
    );
  }
  return sawIgnored ? NaturalDateResult(text, null, skipped: true) : none;
}
