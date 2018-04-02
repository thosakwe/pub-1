// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../exceptions.dart';
import '../flutter.dart' as flutter;
import '../log.dart' as log;
import '../package_name.dart';
import '../sdk.dart' as sdk;
import '../utils.dart';
import 'incompatibility.dart';
import 'incompatibility_cause.dart';
import 'set_relation.dart';
import 'term.dart';

/// Tries to simplify the derivation graph of [incompatibility] by rearranging
/// the derivations to minimize the number of incompatibilities that have
/// three or more terms.
///
/// Many-term incompatibilities tend to be harder to understand than two-term
/// incompatibilities. This looks for the place where many-term
/// incompatibilities are reduced to fewer terms, and tries to push that
/// reduction further back in the derivation graph. For example, given the
/// derivation graph:
///
///     {Q, not R, not S}   {S, not T}
///       │   ┌─────────────────┘
///       ▼   ▼
///     {Q, not R, not T}   {R}
///       │   ┌──────────────┘
///       ▼   ▼
///     {Q, not T}
///
/// This moves the cause `{R}` up one link in the chain:
///
///     {Q, not R, not S}   {R}
///       │   ┌──────────────┘
///       ▼   ▼
///     {Q, not S}   {S, not T}
///       │   ┌──────────┘
///       ▼   ▼
///     {Q, not T}
///
/// This is done iteratively so that, in most cases, it's able to entirely
/// eliminate many-term incompatibilities.
Incompatibility simplify(Incompatibility incompatibility) {
  if (incompatibility.cause is! ConflictCause) return incompatibility;
  var cause = incompatibility.cause as ConflictCause;

  Incompatibility reducer; // {myapp, intl ^5.0.0}
  Incompatibility reducee; // {menu any, not intl ^4.0.0, not icons ^2.0.0}
  // incompatibility: {menu any, not icons ^2.0.0}
  if (incompatibility.terms.length < cause.conflict.terms.length) {
    reducee = cause.conflict;
    reducer = cause.other;
  } else if (incompatibility.terms.length < cause.other.terms.length) {
    reducee = cause.other;
    reducer = cause.conflict;
  } else {
    return _simplifyParents(incompatibility);
  }

  if (reducee.terms.length < 3 || reducee.cause is! ConflictCause) {
    return _simplifyParents(incompatibility);
  }
  var reduceeCause = reducee.cause as ConflictCause;
  var removed = reducee.terms.firstWhere((reduceeTerm) => !incompatibility.terms.any((resultTerm) => reduceeTerm.package.name == resultTerm.package.name))
    ; // not intl ^4.0.0

  Incompatibility sourceParent;
  Incompatibility otherParent;
  if (reduceeCause.conflict.terms.any((term) => term.satisfies(removed))) {
    sourceParent = reduceeCause.conflict;
    otherParent = reduceeCause.other;
  } else if (reduceeCause.other.terms.any((term) => term.satisfies(removed))) {
    sourceParent = reduceeCause.other;
    otherParent = reduceeCause.conflict;
  } else {
    return _simplifyParents(incompatibility);
  }

  var newParent = _resolve(sourceParent, reducer);
  if (newParent.terms.length >= reducee.terms.length) {
    return _simplifyParents(incompatibility);
  }

  return simplify(_resolve(newParent, otherParent));
}

Incompatibility _simplifyParents(Incompatibility incompatibility) {
  var cause = incompatibility.cause as ConflictCause;
    var conflict = simplify(cause.conflict);
    var other = simplify(cause.other);
    if (identical(conflict, cause.conflict) && identical(other, cause.other)) {
      return incompatibility;
    } else {
      return new Incompatibility(incompatibility.terms, new ConflictCause(conflict, other));
    }
}

Incompatibility _resolve(Incompatibility incompatibility1, Incompatibility incompatibility2) {
  String removedPackage;
  Term union;
  for (var term1 in incompatibility1.terms) {
    for (var term2 in incompatibility2.terms) {
      if (term1.package.name != term2.package.name) continue;

      removedPackage = term1.package.name;
      union = term1.union(term2);
    }
  }

  if (removedPackage == null) {
    throw new ArgumentError("$incompatibility1 can't be resolved with $incompatibility2.");
  }

  var newTerms = incompatibility1.terms.where((term) => term.package.name != removedPackage).toList()..addAll(incompatibility2.terms.where((term) => term.package.name != removedPackage));
  if (union != null) newTerms.add(union);

  var result = new Incompatibility(newTerms,
      new ConflictCause(incompatibility1, incompatibility2));
  return result;
}
