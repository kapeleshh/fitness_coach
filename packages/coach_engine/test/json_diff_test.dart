import 'package:test/test.dart';

import 'support/json_diff.dart';

void main() {
  test('equal JSON has no differences', () {
    expect(jsonDiff({'a': [1, 2.5, null, 'x']}, {'a': [1, 2.5, null, 'x']}), isEmpty);
  });

  test('reports each mismatch with its path', () {
    expect(jsonDiff({'a': 1, 'b': [1, 2]}, {'a': 2, 'b': [1, 3]}),
        [r'$.a: 1, expected 2', r'$.b[1]: 2, expected 3']);
  });

  test('an int where Python has a float is a mismatch, and vice versa', () {
    expect(jsonDiff(71, 71.0), hasLength(1));
    expect(jsonDiff(71.0, 71), hasLength(1));
  });

  test('missing and unexpected keys are reported', () {
    expect(jsonDiff({'a': 1}, {'b': 1}),
        unorderedEquals([r'$.a: unexpected 1', r'$.b: missing (expected 1)']));
  });

  test('floats may differ only in their last bits', () {
    expect(jsonDiff(0.1 + 0.2, 0.3), isEmpty);
    expect(jsonDiff(0.3001, 0.3), hasLength(1));
  });
}
