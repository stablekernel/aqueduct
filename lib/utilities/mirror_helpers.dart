import 'dart:mirrors';

import '../aqueduct.dart';

bool doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(ManagedObject);
  var orderedSetMirror = reflectType(ManagedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  }

  return false;
}

ManagedTransientAttribute transientFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedTransientAttribute, dm);
ManagedColumnAttributes attributeMetadataFromDeclaration(
        DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedColumnAttributes, dm);
ManagedRelationship belongsToMetadataFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedRelationship, dm);

dynamic metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}
