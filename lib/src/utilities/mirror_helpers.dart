import 'dart:mirrors';

dynamic metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}