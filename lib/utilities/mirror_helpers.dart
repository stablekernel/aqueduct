part of aqueduct;

bool _doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(Model);
  var orderedSetMirror = reflectType(OrderedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  }

  return false;
}

TransientAttribute _mappableFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(TransientAttribute, dm);
AttributeHint _attributeMetadataFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(AttributeHint, dm);
RelationshipInverse _belongsToMetadataFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(RelationshipInverse, dm);

dynamic _metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}

