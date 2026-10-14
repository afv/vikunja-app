/// Client-side mirror of the server's search rule, used to sort search results: every word of the query must
/// appear in the text, in any order, ignoring case and accents ("tes not io" matches "Test notification íóú").
library;

const _folds = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ł': 'l',
  'ř': 'r',
  'ď': 'd',
  'ť': 't',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
};

/// Lower case without accents.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_folds[ch] ?? ch);
  }
  return out.toString();
}

/// True when every word of [query] appears in [text] (case- and accent-insensitive).
bool matchesAllWords(String text, String query) {
  final folded = foldForSearch(text);
  final words = foldForSearch(
    query,
  ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  return words.isNotEmpty && words.every(folded.contains);
}

/// True when [query] names the task by number, mirroring the server: "208" or "#208" is the task id, "#9" is also
/// the task's number in its project, "REP-9" (any case) is its identifier, and "REP-" names every task of REP.
bool matchesTaskReference(int id, String identifier, String query) {
  final q = query.trim().toUpperCase();
  final number = RegExp(r'^#?(\d+)$').firstMatch(q);
  if (number != null) {
    final n = number.group(1)!;
    if (int.tryParse(n) == id) return true;
    if (!q.startsWith('#')) return false;
    final ident = identifier.toUpperCase();
    return ident == '#$n' || ident.endsWith('-$n');
  }
  if (!RegExp(r'^[\p{L}\p{N}]+-\d*$', unicode: true).hasMatch(q)) return false;
  final ident = identifier.toUpperCase();
  return q.endsWith('-') ? ident.startsWith(q) : ident == q;
}
