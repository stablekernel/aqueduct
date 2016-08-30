part of aqueduct;


Mappable _mappableFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(Mappable, dm);
Attributes _attributeMetadataFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(Attributes, dm);
Relationship _relationshipFromDeclaration(DeclarationMirror dm) => _metadataFromDeclaration(Relationship, dm);

dynamic _metadataFromDeclaration(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata
      .firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)
      ?.reflectee;
}