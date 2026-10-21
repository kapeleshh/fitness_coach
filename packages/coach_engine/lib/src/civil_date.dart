/// A calendar date with no time of day or time zone, like Python's
/// `datetime.date`.
///
/// Arithmetic goes through UTC midnight, so a daylight-saving change can
/// never shift a day. Windows such as "the last 7 days" are counted in
/// calendar days, as in the Python engines, so a missing record never
/// shifts a pairing.
class CivilDate implements Comparable<CivilDate> {
  CivilDate(int year, int month, int day) : this._(DateTime.utc(year, month, day));

  CivilDate._(DateTime utc) : _utc = DateTime.utc(utc.year, utc.month, utc.day);

  /// Parses `YYYY-MM-DD`, as `date.fromisoformat` does for the dates the
  /// engines store. Throws [FormatException] for anything else, including
  /// dates that don't exist such as `2026-02-30`.
  factory CivilDate.parse(String text) {
    final match = _iso.firstMatch(text);
    if (match == null) throw FormatException('Invalid isoformat string', text);
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = CivilDate(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('day is out of range for month', text);
    }
    return date;
  }

  /// [CivilDate.parse], or null when [text] is null or not a valid date.
  static CivilDate? tryParse(Object? text) {
    if (text is! String) return null;
    try {
      return CivilDate.parse(text);
    } on FormatException {
      return null;
    }
  }

  static final _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final DateTime _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// Monday is 0 and Sunday is 6, as in Python's `date.weekday()`.
  int get weekday => _utc.weekday - 1;

  CivilDate addDays(int days) => CivilDate._(_utc.add(Duration(days: days)));

  /// Whole days from [other] to this date, like `(self - other).days`.
  int daysSince(CivilDate other) => _utc.difference(other._utc).inDays;

  bool operator <(CivilDate other) => compareTo(other) < 0;
  bool operator <=(CivilDate other) => compareTo(other) <= 0;
  bool operator >(CivilDate other) => compareTo(other) > 0;
  bool operator >=(CivilDate other) => compareTo(other) >= 0;

  @override
  int compareTo(CivilDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) => other is CivilDate && other._utc == _utc;

  @override
  int get hashCode => _utc.hashCode;

  /// `YYYY-MM-DD`, like `date.isoformat()`.
  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
