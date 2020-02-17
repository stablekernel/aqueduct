import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/http/resource_controller_interfaces.dart';
import 'package:aqueduct/src/runtime/resource_controller/documenter.dart';
import 'package:aqueduct/src/runtime/resource_controller/utility.dart';
import 'package:aqueduct/src/runtime/resource_controller_generator.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:meta/meta.dart';
import 'package:runtime/runtime.dart' hide firstMetadataOfType;

class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {
  ResourceControllerRuntimeImpl(this.type) {
    final allDeclarations = type.declarations;

    ivarParameters = allDeclarations.values
        .whereType<VariableMirror>()
        .where((decl) => decl.metadata.any((im) => im.reflectee is Bind))
        .map((decl) {
      final isRequired = allDeclarations[decl.simpleName]
          .metadata
          .any((im) => im.reflectee is RequiredBinding);
      return getParameterForVariable(decl, isRequired: isRequired);
    }).toList();

    operations = type.instanceMembers.values
        .where(isOperation)
        .map(getOperationForMethod)
        .toList();

    if (conflictingOperations.isNotEmpty) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has "
          "ambiguous operations. Offending operating methods: $opNames.");
    }

    if (unsatisfiableOperations.isNotEmpty) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has operations where "
          "parameter is bound with @Bind.path(), but path variable is not declared in "
          "@Operation(). Offending operation methods: $opNames");
    }

    documenter = ResourceControllerDocumenterImpl(this);
  }

  final ClassMirror type;

  String compile(BuildContext ctx) =>
      getResourceControllerImplSource(this, ctx);

  List<String> get unsatisfiableOperations {
    return operations
        .where((op) {
          final argPathParameters = op.positionalParameters
              .where((p) => p.location == BindingType.path);

          return !argPathParameters
              .every((p) => op.pathVariables.contains(p.name));
        })
        .map((op) => op.dartMethodName)
        .toList();
  }

  List<String> get conflictingOperations {
    return operations
        .where((op) {
          final possibleConflicts = operations.where((b) => b != op);

          return possibleConflicts.any((opToCompare) {
            if (opToCompare.httpMethod != op.httpMethod) {
              return false;
            }

            if (opToCompare.pathVariables.length != op.pathVariables.length) {
              return false;
            }

            return opToCompare.pathVariables
                .every((p) => op.pathVariables.contains(p));
          });
        })
        .map((op) => op.dartMethodName)
        .toList();
  }

  ResourceControllerParameter getParameterForVariable(VariableMirror mirror,
      {@required bool isRequired}) {
    final metadata = mirror.metadata
        .firstWhere((im) => im.reflectee is Bind)
        .reflectee as Bind;

    if (mirror.type is! ClassMirror) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(mirror.simpleName)}' on '${getMethodAndClassName(mirror)}': "
          "'${MirrorSystem.getName(mirror.type.simpleName)}'. Cannot bind dynamic parameters.");
    }
    final boundType = mirror.type as ClassMirror;

    try {
      if (boundType.isAssignableTo(reflectType(List))) {
        _enforceTypeCanBeParsedFromString(boundType.typeArguments.first);
      } else {
        _enforceTypeCanBeParsedFromString(boundType);
      }
    } catch (e) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(mirror.simpleName)}' on '${getMethodAndClassName(mirror)}': "
          "$e");
    }

    if (metadata.bindingType == BindingType.body) {
      final _isBoundToSerializable =
          boundType.isSubtypeOf(reflectType(Serializable));

      final _isBoundToListOfSerializable = boundType
              .isSubtypeOf(reflectType(List)) &&
          boundType.typeArguments.first.isSubtypeOf(reflectType(Serializable));
      if (metadata.ignore != null ||
          metadata.reject != null ||
          metadata.require != null) {
        if (!(_isBoundToSerializable || _isBoundToListOfSerializable)) {
          throw StateError(
              "Invalid binding '${MirrorSystem.getName(mirror.simpleName)}' on '${getMethodAndClassName(mirror)}': "
              "Filters can only be used on Serializable or List<Serializable>.");
        }
      }
    }

    return ResourceControllerParameter(
        name: metadata.name,
        type: mirror.type.reflectedType,
        symbolName: MirrorSystem.getName(mirror.simpleName),
        location: metadata.bindingType,
        isRequired: isRequired,
        decode: (req) {});
  }

  ResourceControllerOperation getOperationForMethod(MethodMirror mirror) {
    final operation = getMethodOperationMetadata(mirror);
    final symbol = mirror.simpleName;

    final parametersWithoutMetadata = mirror.parameters
        .where((p) => firstMetadataOfType<Bind>(p) == null)
        .toList();
    if (parametersWithoutMetadata.isNotEmpty) {
      final names = parametersWithoutMetadata
          .map((p) => "'${MirrorSystem.getName(p.simpleName)}'")
          .join(", ");
      throw StateError("Invalid operation method parameter(s) $names on "
          "'${getMethodAndClassName(parametersWithoutMetadata.first)}': Must have @Bind annotation.");
    }

    return ResourceControllerOperation(
        positionalParameters: mirror.parameters
            .where((pm) => !pm.isOptional)
            .map((pm) => getParameterForVariable(pm, isRequired: true))
            .toList(),
        namedParameters: mirror.parameters
            .where((pm) => pm.isOptional)
            .map((pm) => getParameterForVariable(pm, isRequired: false))
            .toList(),
        scopes: getMethodScopes(mirror),
        dartMethodName: MirrorSystem.getName(symbol),
        httpMethod: operation.method.toUpperCase(),
        pathVariables: operation.pathVariables,
        invoker: (rc, req, args) {
          final rcMirror = reflect(rc);

          args.instanceVariables.forEach(rcMirror.setField);

          return rcMirror
              .invoke(symbol, args.positionalArguments, args.namedArguments)
              .reflectee as Future<Response>;
        });
  }
}

void _enforceTypeCanBeParsedFromString(TypeMirror typeMirror) {
  if (typeMirror is! ClassMirror) {
    throw 'Cannot bind dynamic type parameters.';
  }

  if (typeMirror.isAssignableTo(reflectType(String))) {
    return;
  }

  final classMirror = typeMirror as ClassMirror;
  if (!classMirror.staticMembers.containsKey(#parse)) {
    throw 'Parameter type does not implement static parse method.';
  }

  final parseMethod = classMirror.staticMembers[#parse];
  final params = parseMethod.parameters.where((p) => !p.isOptional).toList();
  if (params.length == 1 &&
      params.first.type.isAssignableTo(reflectType(String))) {
    return;
  }

  throw 'Invalid parameter type.';
}
