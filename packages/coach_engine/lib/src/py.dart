/// Python's numeric behaviour, reproduced where the engines depend on it.
///
/// The Python engines are the reference. A sum that differs in its last bit,
/// or a tie rounded the other way, changes a reported number or a word in a
/// briefing, so these helpers copy CPython exactly rather than approximately.
/// `test/py_test.dart` checks them against cases Python itself produced.
library;

import 'dart:typed_data';

final BigInt _ten = BigInt.from(10);
final BigInt _five = BigInt.from(5);

/// Python's `sum()`.
///
/// Integers add exactly while every value is an int. From the first float on
/// the total is a float: floats are added with Neumaier's compensated
/// summation, as CPython 3.12 and later do, and the compensation is applied
/// once at the end.
num pySum(Iterable<num> values) {
  final it = values.iterator;
  var intTotal = 0;
  while (it.moveNext()) {
    final first = it.current;
    if (first is int) {
      intTotal += first;
      continue;
    }
    var total = intTotal + first.toDouble();
    var compensation = 0.0;
    while (it.moveNext()) {
      final x = it.current.toDouble();
      final t = total + x;
      if (total.abs() >= x.abs()) {
        compensation += (total - t) + x;
      } else {
        compensation += (x - t) + total;
      }
      total = t;
    }
    if (compensation != 0.0 && compensation.isFinite) {
      total += compensation;
    }
    return total;
  }
  return intTotal;
}

/// Python's `round(x)` when [ndigits] is null (an int, ties to even), and
/// `round(x, ndigits)` otherwise (a float rounded on its exact binary value,
/// ties to even). Ints come back unchanged, as in Python.
num pyRound(num x, [int? ndigits]) {
  if (x is int) return x;
  final value = x.toDouble();
  if (!value.isFinite) {
    if (ndigits == null) {
      throw UnsupportedError('cannot round $value to an integer');
    }
    return value;
  }
  if (ndigits != null && ndigits < 0) {
    throw ArgumentError.value(ndigits, 'ndigits', 'negative ndigits not supported');
  }
  final exact = _exactDecimal(value);
  final rounded = _roundHalfEven(exact.digits, exact.scale, ndigits ?? 0);
  if (ndigits == null) {
    final asInt = rounded.toInt();
    return exact.negative ? -asInt : asInt;
  }
  return double.parse('${exact.negative ? '-' : ''}${rounded}e-$ndigits');
}

/// Python's `format(x, '.Nf')`, or `format(x, '+.Nf')` when [sign] is true,
/// as f-strings such as `f"{x:+.1f}"` use it. A negative value that rounds
/// to zero keeps its sign ("-0"), as in Python.
String pyFixed(num x, int digits, {bool sign = false}) {
  final value = x.toDouble();
  if (value.isNaN) return sign ? '+nan' : 'nan';
  if (value.isInfinite) return value > 0 ? (sign ? '+inf' : 'inf') : '-inf';
  final exact = _exactDecimal(value);
  var text = _roundHalfEven(exact.digits, exact.scale, digits)
      .toString()
      .padLeft(digits + 1, '0');
  if (digits > 0) {
    final point = text.length - digits;
    text = '${text.substring(0, point)}.${text.substring(point)}';
  }
  return '${exact.negative ? '-' : (sign ? '+' : '')}$text';
}

/// Python's `repr()` of a float, which is also what `str()` and an f-string
/// without a format spec show.
String pyRepr(double x) {
  if (x.isNaN) return 'nan';
  if (x.isInfinite) return x > 0 ? 'inf' : '-inf';
  if (x == 0) return x.isNegative ? '-0.0' : '0.0';
  final magnitude = x.abs();
  if (magnitude >= 1e-4 && magnitude < 1e16) {
    // Dart and Python agree here: shortest round-trip digits, and a
    // trailing ".0" on whole numbers.
    return x.toString();
  }
  // Python writes the exponent with a sign and at least two digits.
  final text = x.toStringAsExponential();
  final e = text.indexOf('e');
  final exponent = text.substring(e + 2).padLeft(2, '0');
  return '${text.substring(0, e)}e${text[e + 1]}$exponent';
}

/// A value as a Python f-string shows it with no format spec.
String pyStr(Object? value) => switch (value) {
      null => 'None',
      true => 'True',
      false => 'False',
      double() => pyRepr(value),
      _ => value.toString(),
    };

/// Python's `statistics.median`: the middle value, or the mean of the two
/// middle values (always a float) when there is an even number of them.
num pyMedian(Iterable<num> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) throw StateError('no median for empty data');
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// [value] as exactly `digits / 10^scale`, with its sign kept apart so that
/// -0.0 stays negative.
({bool negative, BigInt digits, int scale}) _exactDecimal(double value) {
  final bytes = ByteData(8)..setFloat64(0, value);
  final high = bytes.getUint32(0);
  final low = bytes.getUint32(4);
  final negative = (high >> 31) == 1;
  final biasedExponent = (high >> 20) & 0x7ff;
  var mantissa = (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
  int exponent;
  if (biasedExponent == 0) {
    exponent = -1074; // subnormal
  } else {
    mantissa |= BigInt.one << 52;
    exponent = biasedExponent - 1075;
  }
  if (exponent >= 0) {
    return (negative: negative, digits: mantissa << exponent, scale: 0);
  }
  // m * 2^-k == m * 5^k / 10^k
  return (negative: negative, digits: mantissa * _five.pow(-exponent), scale: -exponent);
}

/// `digits / 10^scale` rounded to [places] decimal places, ties to even,
/// returned as the integer `round(value * 10^places)`.
BigInt _roundHalfEven(BigInt digits, int scale, int places) {
  if (scale <= places) return digits * _ten.pow(places - scale);
  final divisor = _ten.pow(scale - places);
  var quotient = digits ~/ divisor;
  final twiceRemainder = (digits - quotient * divisor) * BigInt.two;
  if (twiceRemainder > divisor || (twiceRemainder == divisor && quotient.isOdd)) {
    quotient += BigInt.one;
  }
  return quotient;
}
