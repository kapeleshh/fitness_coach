import 'package:test/test.dart';

/// Differences between an engine result and the Python fixture, one line
/// per mismatch with its JSON path, so a failing parity test points at the
/// exact field.
///
/// Ints and floats must match in type as well as value, as they do in the
/// JSON both sides produce. Floats may differ only in their last bits, which
/// allows for `log` and `exp` rounding differently in another libm.
List<String> jsonDiff(Object? actual, Object? expected, [String path = r'$']) {
  final out = <String>[];
  _walk(actual, expected, path, out);
  return out;
}

/// Matches when [jsonDiff] finds no differences from [expected].
Matcher sameJson(Object? expected) => _SameJson(expected);

const _relativeTolerance = 1e-12;

void _walk(Object? a, Object? e, String path, List<String> out) {
  if (e is Map) {
    if (a is! Map) {
      out.add('$path: expected an object, got ${_show(a)}');
      return;
    }
    for (final key in {...e.keys, ...a.keys}) {
      if (!a.containsKey(key)) {
        out.add('$path.$key: missing (expected ${_show(e[key])})');
      } else if (!e.containsKey(key)) {
        out.add('$path.$key: unexpected ${_show(a[key])}');
      } else {
        _walk(a[key], e[key], '$path.$key', out);
      }
    }
  } else if (e is List) {
    if (a is! List) {
      out.add('$path: expected a list, got ${_show(a)}');
      return;
    }
    if (a.length != e.length) out.add('$path: length ${a.length}, expected ${e.length}');
    for (var i = 0; i < a.length && i < e.length; i++) {
      _walk(a[i], e[i], '$path[$i]', out);
    }
  } else if (e is num) {
    if (a is! num) {
      out.add('$path: ${_show(a)}, expected ${_show(e)}');
    } else if ((a is int) != (e is int)) {
      out.add('$path: ${_show(a)} (${a is int ? 'int' : 'float'}), '
          'expected ${_show(e)} (${e is int ? 'int' : 'float'})');
    } else if (a != e) {
      final scale = e.abs() > 1 ? e.abs() : 1;
      if ((a - e).abs() > _relativeTolerance * scale) {
        out.add('$path: ${_show(a)}, expected ${_show(e)}');
      }
    }
  } else if (a != e) {
    out.add('$path: ${_show(a)}, expected ${_show(e)}');
  }
}

String _show(Object? v) => v is String ? '"$v"' : '$v';

class _SameJson extends Matcher {
  _SameJson(this.expected);

  final Object? expected;

  @override
  bool matches(Object? item, Map matchState) {
    final diff = jsonDiff(item, expected);
    matchState['diff'] = diff;
    return diff.isEmpty;
  }

  @override
  Description describe(Description description) =>
      description.add('the same JSON as the Python fixture');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map matchState,
    bool verbose,
  ) {
    final diff = matchState['diff'] as List<String>;
    final shown = diff.take(15).join('\n');
    final more = diff.length > 15 ? '\n... and ${diff.length - 15} more' : '';
    return mismatchDescription.add('differs:\n$shown$more');
  }
}
