import 'dart:mirrors';

dynamic firstMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}

List<dynamic> allMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .where((im) => im.type.isSubtypeOf(tMirror))
      .map((im) => im.reflectee)
      .toList();
}