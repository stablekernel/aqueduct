import 'dart:mirrors';
import 'managed.dart';
import '../../utilities/mirror_helpers.dart';

List<VariableMirror> instanceVariableMirrorsFromClass(ClassMirror classMirror) {
  return classHierarchyForClass(classMirror)
      .expand((cm) => cm.declarations
        .values
        .where(isInstanceVariableMirror)
        .map((d) => d as VariableMirror))
      .toList();
}

VariableMirror variableMirrorFromClass(ClassMirror classMirror, Symbol name) {
  return classHierarchyForClass(classMirror)
      .expand((cm) => cm.declarations.values)
      .firstWhere((dm) => dm.simpleName == name,
        orElse: () => null);
}

ManagedAttributeDescription attributeDescriptionFromDeclaration(ManagedEntity entity,
    DeclarationMirror declarationMirror) {
  var name = MirrorSystem.getName(declarationMirror.simpleName);
  ManagedPropertyType type;
  ManagedTransientAttribute transience;

  if (declarationMirror is MethodMirror) {
    // This is from an accessor method declared in the instance type.
    var propertyType;
    if (declarationMirror.isGetter) {
      propertyType = declarationMirror.returnType.reflectedType;
      transience = new ManagedTransientAttribute(availableAsOutput: true);
    } else if (declarationMirror.isSetter) {
      name = name.substring(0, name.length - 1);
      propertyType = declarationMirror.parameters.first.type.reflectedType;
      transience = new ManagedTransientAttribute(availableAsInput: true);
    }

    type = ManagedPropertyDescription.propertyTypeForDartType(propertyType);
  } else if (declarationMirror is VariableMirror) {
    var propertyType
    if (entity.instanceType == declarationMirror.owner) {
      // 'Transient', declared in instance type
      propertyType = declarationMirror.type.reflectedType;
    } else {
      // Persistent
    }

    type = ManagedPropertyDescription.propertyTypeForDartType(propertyType);
  }
  /*
  if (type == null) {
        throw new ManagedDataModelException.invalidType(
            entity, mirror.simpleName);
      }
   */
  return new ManagedAttributeDescription.transient(
      entity,
      name,

      transience);
}

bool isInstanceVariableMirror(DeclarationMirror mirror) =>
    mirror is VariableMirror && !mirror.isStatic;

bool hasTransientMetadata(DeclarationMirror mirror) =>
    transientFromDeclaration(mirror) != null;

bool isTransientAccessorMethod(DeclarationMirror declMir) {
  if (declMir is! MethodMirror) {
    return false;
  }

  var methodMirror = declMir as MethodMirror;
  if (methodMirror.isStatic) {
    return false;
  }

  if (!(methodMirror.isSetter || methodMirror.isGetter) || methodMirror.isSynthetic) {
    return false;
  }

  var mapMetadata = transientFromDeclaration(declMir);
  if (mapMetadata == null) {
    return false;
  }

  // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
  return (methodMirror.isSetter && mapMetadata.isAvailableAsInput)
      || (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
}

bool doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(ManagedObject);
  var orderedSetMirror = reflectType(ManagedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  } else if (managedRelationshipMetadataFromDeclaration(mirror)?.isDeferred ?? false) {
    return true;
  }

  return false;
}

ManagedTransientAttribute transientFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedTransientAttribute, dm);
ManagedColumnAttributes attributeMetadataFromDeclaration(
    DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedColumnAttributes, dm);
ManagedRelationship managedRelationshipMetadataFromDeclaration(DeclarationMirror dm) =>
    metadataFromDeclaration(ManagedRelationship, dm);

Iterable<ClassMirror> classHierarchyForClass(ClassMirror t) sync* {
  var persistentTypePtr = t;
  while (persistentTypePtr.superclass != null) {
    yield persistentTypePtr;
    persistentTypePtr = persistentTypePtr.superclass;
  }
}