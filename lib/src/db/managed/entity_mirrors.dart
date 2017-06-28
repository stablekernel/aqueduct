import 'dart:mirrors';
import 'managed.dart';
import 'validate.dart';
import '../../utilities/mirror_helpers.dart';

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
      })
      .toList();
}

VariableMirror instanceVariableFromClass(ClassMirror classMirror, Symbol name) {
  return instanceVariablesFromClass(classMirror)
      .firstWhere((dm) => dm.simpleName == name, orElse: () => null);
}

ManagedPropertyType propertyTypeFromDeclaration(DeclarationMirror declaration) {
  if (declaration is MethodMirror) {
    ClassMirror type;

    if (declaration.isGetter) {
      type = declaration.returnType;
    } else if (declaration.isSetter) {
      type = declaration.parameters.first.type;
    }

    return ManagedPropertyDescription
        .propertyTypeForDartType(type.reflectedType);
  } else if (declaration is VariableMirror) {
    var attributes = attributeMetadataFromDeclaration(declaration);

    return attributes?.databaseType ??
        ManagedPropertyDescription
            .propertyTypeForDartType(declaration.type.reflectedType);
  }

  throw new ManagedDataModelException(
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

  throw new ManagedDataModelException(
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

List<Validate> validatorsFromDeclaration(DeclarationMirror dm) =>
  allMetadataOfType(Validate, dm);
ManagedTransientAttribute transientMetadataFromDeclaration(
        DeclarationMirror dm) =>
    firstMetadataOfType(ManagedTransientAttribute, dm);
ManagedColumnAttributes attributeMetadataFromDeclaration(
        DeclarationMirror dm) =>
    firstMetadataOfType(ManagedColumnAttributes, dm);
ManagedRelationship relationshipMetadataFromProperty(DeclarationMirror dm) =>
    firstMetadataOfType(ManagedRelationship, dm);

Iterable<ClassMirror> classHierarchyForClass(ClassMirror t) sync* {
  var persistentTypePtr = t;
  while (persistentTypePtr.superclass != null) {
    yield persistentTypePtr;
    persistentTypePtr = persistentTypePtr.superclass;
  }
}
