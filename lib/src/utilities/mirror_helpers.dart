import 'dart:mirrors';

import '../db/managed/object.dart';
import '../db/managed/set.dart';
import '../db/managed/attributes.dart';

bool doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(ManagedObject);
  var orderedSetMirror = reflectType(ManagedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  } else if (doesVariableMirrorReferencePartialManagedObject(mirror)) {
    return true;
  }

  return false;
}

bool doesVariableMirrorReferencePartialManagedObject(VariableMirror mirror) {
  return mirror.metadata
      .firstWhere((im) => im.reflectee == managedPartialObject,
      orElse: () => null) != null;
}

ManagedTransientAttribute transientFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedTransientAttribute, dm);
ManagedColumnAttributes attributeMetadataFromDeclaration(
        DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedColumnAttributes, dm);
ManagedRelationship managedRelationshipMetadataFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedRelationship, dm);

dynamic metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}
