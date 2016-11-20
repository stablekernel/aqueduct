part of aqueduct;

bool _doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(ManagedObject);
  var orderedSetMirror = reflectType(ManagedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  }

  return false;
}

ManagedTransientAttribute _transientFromDeclaration(DeclarationMirror dm) =>
    _metadataFromDeclaration(ManagedTransientAttribute, dm);
ManagedColumnAttributes _attributeMetadataFromDeclaration(
        DeclarationMirror dm) =>
    _metadataFromDeclaration(ManagedColumnAttributes, dm);
ManagedRelationship _belongsToMetadataFromDeclaration(DeclarationMirror dm) =>
    _metadataFromDeclaration(ManagedRelationship, dm);

dynamic _metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}
