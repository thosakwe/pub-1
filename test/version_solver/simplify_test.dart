// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:pub/src/package_name.dart';
import 'package:pub/src/solver/failure.dart';
import 'package:pub/src/solver/incompatibility.dart';
import 'package:pub/src/solver/incompatibility_cause.dart';
import 'package:pub/src/solver/term.dart';
import 'package:pub/src/source/hosted.dart';

final _hosted = new HostedSource();

void main() {
  test("doesn't simplify an incompatibility with only two terms", () {
    var parent = _conflict(["x", "not b"], _depends("x", "a"), _depends("a", "b"));
    _expectFailureString(_conflict(["x"], parent, _forbidden("b")), """
      Because every version of x depends on a any which depends on b any, every
        version of x requires b any.
      So, because b is forbidden, x is forbidden.
    """);
  });

  test("simplifies an incompatibility with three terms", () {
    var parent = _conflict(["x", "not a", "not b <1.0.0"], _depends("x", "b"), _depends("b >=1.0.0", "a"));
    parent = _conflict(["x", "not b <1.0.0", "not c"], parent, _depends("a", "c"));
    _expectFailureString(_conflict(["x", "not b <1.0.0"], parent, _forbidden("c")), """
      Because every version of a depends on c any which is forbidden, a is
        forbidden.
      So, because b >=1.0.0 depends on a any and every version of x depends on b
        any, every version of x requires b <1.0.0.
    """);
  });

  test("bubbles up a partial satisfier", () {
    var parent = _conflict(["x", "not a", "not b <1.0.0"], _depends("x", "b"), _depends("b >=1.0.0", "a"));
    parent = _conflict(["x", "not b <1.0.0", "not c"], parent, _depends("a", "c"));
    _expectFailureString(_conflict(["x", "not c"], parent, _forbidden("b <1.0.0")), """
      Because every version of x depends on b any and b <1.0.0 is forbidden,
        every version of x requires b >=1.0.0.
      So, because b >=1.0.0 depends on a any which depends on c any, every
        version of x requires c any.
    """);
  });
}

/// Creates an incompatibility with the given [terms] (as parsed by [_term]) and
/// no particular cause.
Incompatibility _incompatibility(List<String> terms) =>
    new Incompatibility(terms.map(_term).toList(), IncompatibilityCause.noReason);

/// Creates an incompatibility with the given [terms] (as parsed by [_term]) and
/// a [ConflictCause] with the causes [conflict] and [other].
Incompatibility _conflict(List<String> terms, Incompatibility conflict, Incompatibility other) =>
    new Incompatibility(terms.map(_term).toList(), new ConflictCause(conflict, other));

/// Creates an incompatibility representing a dependency from [depender] onto
/// [target] (parsed by [_term]).
Incompatibility _depends(String depender, String target) =>
  new Incompatibility([_term(depender), _term(target).inverse], IncompatibilityCause.dependency);

/// Creates an incompatibility indicating that [package] (parsed by [_term]) is
/// forbidden.
Incompatibility _forbidden(String package) =>
  new Incompatibility([_term(package)], IncompatibilityCause.noReason);

/// Parses [description], which should be of the form `[not] $name
/// [$constraint]`.
///
/// If the constraint is omitted, it defaults to `any`.
Term _term(String description) {
  var components = description.split(" ");
  assert(components.length <= 3);
  assert(components.length > 0);

  var isPositive = components.first != "not";
  if (!isPositive) components.removeAt(0);
  var name = components.first;
  var constraint = components.length > 1 ? new VersionConstraint.parse(components[1]) : VersionConstraint.any;
  return new Term(new PackageRange(name, _hosted, constraint, name), isPositive);
}

/// Asserts that the string representation of [incompatibility]'s derivation
/// graph matches [message], ignoring whitespace.
void _expectFailureString(Incompatibility incompatibility, String message) {
  expect(new SolveFailure(incompatibility).toString(), equalsIgnoringWhitespace(message));
}
