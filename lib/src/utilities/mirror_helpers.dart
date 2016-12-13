import 'dart:mirrors';

import '../db/managed/object.dart';
import '../db/managed/set.dart';
import '../db/managed/attributes.dart';

dynamic metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}
