import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/validation/metadata.dart';

import '../../utilities/mirror_helpers.dart';
import 'managed.dart';

// Expanding the list of ivars for each class yields duplicates of
// any ivar is overridden. Since the order in which ivars are returned
// is known (a subclass' ivars always come before its superclass'),
// we can simply fold this list so that the first ivar 'wins'.
List<VariableMirror> instanceVariablesFromClass(ClassMirror classMirror) {
  return classHierarchyForClass(classMirror)
      .expand((cm) => cm.declarations.values
          .where(isInstanceVariableMirror)
          .map((decl) => decl as VariableMirror))
      .fold(<VariableMirror>[], (List<VariableMirror> acc, decl) {
    if (!acc.any((vm) => vm.simpleName == decl.simpleName)) {
      acc.add(decl);
    }

    return acc;
  }).toList();
}

bool classHasDefaultConstructor(ClassMirror type) {
  return type.declarations.values.any((dm) {
    return dm is MethodMirror &&
        dm.isConstructor &&
        dm.constructorName == const Symbol('') &&
        dm.parameters.every((p) => p.isOptional == true);
  });
}

VariableMirror instanceVariableFromClass(ClassMirror classMirror, Symbol name) {
  return instanceVariablesFromClass(classMirror)
      .firstWhere((dm) => dm.simpleName == name, orElse: () => null);
}

ClassMirror dartTypeFromDeclaration(DeclarationMirror declaration) {
  if (declaration is MethodMirror) {
    TypeMirror type;

    if (declaration.isGetter) {
      type = declaration.returnType;
    } else if (declaration.isSetter) {
      type = declaration.parameters.first.type;
    }

    if (type is! ClassMirror) {
      throw ManagedDataModelError(
          "Invalid type for field '${MirrorSystem.getName(declaration.simpleName)}'"
          " in type '${MirrorSystem.getName(declaration.owner.simpleName)}'.");
    }
    return type as ClassMirror;
  } else if (declaration is VariableMirror) {
    if (declaration.type is! ClassMirror) {
      throw ManagedDataModelError(
          "Invalid type for field '${MirrorSystem.getName(declaration.simpleName)}'"
          " in type '${MirrorSystem.getName(declaration.owner.simpleName)}'.");
    }
    return declaration.type as ClassMirror;
  }

  throw ManagedDataModelError(
      "Tried getting property type description from non-property. This is an internal error, "
      "as this method shouldn't be invoked on non-property or non-accessors.");
}

ManagedType propertyTypeFromDeclaration(DeclarationMirror declaration) {
  try {
    if (declaration is MethodMirror) {
      TypeMirror type;

      if (declaration.isGetter) {
        type = declaration.returnType;
      } else if (declaration.isSetter) {
        type = declaration.parameters.first.type;
      }

      return ManagedType(type);
    } else if (declaration is VariableMirror) {
      var attributes = attributeMetadataFromDeclaration(declaration);

      if (attributes?.databaseType != null) {
        return ManagedType.fromKind(attributes.databaseType);
      }

      return ManagedType(declaration.type);
    }
  } on UnsupportedError catch (e) {
    throw ManagedDataModelError("Invalid declaration "
        "'${MirrorSystem.getName(declaration.owner.simpleName)}.${MirrorSystem.getName(declaration.simpleName)}'. "
        "Reason: $e");
  }

  throw ManagedDataModelError(
      "Tried getting property type description from non-property. This is an internal error, "
      "as this method shouldn't be invoked on non-property or non-accessors.");
}

String propertyNameFromDeclaration(DeclarationMirror declaration) {
  if (declaration is MethodMirror) {
    if (declaration.isGetter) {
      return MirrorSystem.getName(declaration.simpleName);
    } else if (declaration.isSetter) {
      var name = MirrorSystem.getName(declaration.simpleName);
      return name.substring(0, name.length - 1);
    }
  } else if (declaration is VariableMirror) {
    return MirrorSystem.getName(declaration.simpleName);
  }

  throw ManagedDataModelError(
      "Tried getting property type description from non-property. This is an internal error, "
      "as this method shouldn't be invoked on non-property or non-accessors.");
}

bool isInstanceVariableMirror(DeclarationMirror mirror) =>
    mirror is VariableMirror && !mirror.isStatic;

bool hasTransientMetadata(DeclarationMirror mirror) =>
    transientMetadataFromDeclaration(mirror) != null;

bool isTransientProperty(DeclarationMirror declaration) {
  return isInstanceVariableMirror(declaration) &&
      hasTransientMetadata(declaration);
}

bool isTransientAccessorMethod(DeclarationMirror declMir) {
  if (declMir is! MethodMirror) {
    return false;
  }

  var methodMirror = declMir as MethodMirror;
  if (methodMirror.isStatic) {
    return false;
  }

  if (!(methodMirror.isSetter || methodMirror.isGetter) ||
      methodMirror.isSynthetic) {
    return false;
  }

  var mapMetadata = transientMetadataFromDeclaration(declMir);
  if (mapMetadata == null) {
    return false;
  }

  // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
  return (methodMirror.isSetter && mapMetadata.isAvailableAsInput) ||
      (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
}

bool isTransientPropertyOrAccessor(DeclarationMirror declaration) {
  return isTransientAccessorMethod(declaration) ||
      isTransientProperty(declaration);
}

bool doesVariableMirrorRepresentRelationship(VariableMirror mirror) {
  var modelMirror = reflectType(ManagedObject);
  var orderedSetMirror = reflectType(ManagedSet);

  if (mirror.type.isSubtypeOf(modelMirror)) {
    return true;
  } else if (mirror.type.isSubtypeOf(orderedSetMirror)) {
    return mirror.type.typeArguments.any((tm) => tm.isSubtypeOf(modelMirror));
  } else if (relationshipMetadataFromProperty(mirror)?.isDeferred ?? false) {
    return true;
  }

  return false;
}

Table attributesFromTableDefinition(ClassMirror typeMirror) =>
    firstMetadataOfType(typeMirror, dynamicType: reflectType(Table));

List<Validate> validatorsFromDeclaration(DeclarationMirror dm) =>
    allMetadataOfType<Validate>(dm);

Serialize transientMetadataFromDeclaration(DeclarationMirror dm) =>
    firstMetadataOfType(dm);

Column attributeMetadataFromDeclaration(DeclarationMirror dm) =>
    firstMetadataOfType(dm);

Relate relationshipMetadataFromProperty(DeclarationMirror dm) =>
    firstMetadataOfType(dm);

Iterable<ClassMirror> classHierarchyForClass(ClassMirror t) sync* {
  var tableDefinitionPtr = t;
  while (tableDefinitionPtr.superclass != null) {
    yield tableDefinitionPtr;
    tableDefinitionPtr = tableDefinitionPtr.superclass;
  }
}
