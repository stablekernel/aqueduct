import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/app/mirror.dart';
import 'package:aqueduct/src/runtime/app/resource_controller_mirror/bindings.dart';
import 'package:aqueduct/src/runtime/app/resource_controller_mirror/parameter.dart';
import 'package:aqueduct/src/runtime/app/resource_controller_mirror/utility.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

class ResourceControllerOperationRuntimeImpl
    extends ResourceControllerOperationRuntime {
  ResourceControllerOperationRuntimeImpl(MethodMirror mirror) {
    final operation = getMethodOperationMetadata(mirror);
    methodSymbol = mirror.simpleName;
    method = operation.method.toUpperCase();
    pathVariables = operation.pathVariables;

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

    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => BoundParameter(pm, isRequired: true))
        .toList();
    optionalParameters = mirror.parameters
        .where((pm) => pm.isOptional)
        .map((pm) => BoundParameter(pm, isRequired: false))
        .toList();

    scopes = getMethodScopes(mirror);
  }

  Symbol methodSymbol;
  List<BoundParameter> positionalParameters = [];
  List<BoundParameter> optionalParameters = [];

  @override
  Future<Response> invoke(ResourceController rc, Request request, List<String> errorsIn) async {
    final mirror = reflect(rc);

    final positionalMethodArguments = positionalParameters
        .map((p) {
          try {
            final value = p.decode(request);
            if (value == null && p.isRequired) {
              errorsIn.add("missing required ${p.binding.type} '${p.name ?? ""}'");
              return null;
            }

            return value;
          } on ArgumentError catch (e) {
            errorsIn.add(e.message as String);
            return null;
          }
        })
        .where((p) => p != null)
        .toList();

    final optionalMethodArguments =
        Map<Symbol, dynamic>.fromEntries(optionalParameters.map((p) {
      try {
        final value = p.decode(request);
        if (value == null) {
          return null;
        }

        return MapEntry(p.symbol, value);
      } on ArgumentError catch (e) {
        errorsIn.add(e.message as String);
        return null;
      }
    }).where((e) => e != null));

    if (errorsIn.isNotEmpty) {
      return null;
    }

    return mirror
        .invoke(
            methodSymbol, positionalMethodArguments, optionalMethodArguments)
        .reflectee as Future<Response>;
  }

  /// Checks if a request's method and path variables will select this binder.
  ///
  /// Note that [requestMethod] may be null; if this is the case, only
  /// path variables are compared.
  @override
  bool isSuitableForRequest(
      String requestMethod, List<String> requestPathVariables) {
    if (requestMethod != null && requestMethod.toUpperCase() != method) {
      return false;
    }

    if (pathVariables.length != requestPathVariables.length) {
      return false;
    }

    return requestPathVariables
        .every((varName) => pathVariables.contains(varName));
  }
}

class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {
  ResourceControllerRuntimeImpl(this.type) {
    final allDeclarations = type.declarations;

    final boundProperties = allDeclarations.values
        .whereType<VariableMirror>()
        .where((decl) => decl.metadata.any((im) => im.reflectee is Bind))
        .map((decl) {
      final isRequired = allDeclarations[decl.simpleName]
          .metadata
          .any((im) => im.reflectee is RequiredBinding);
      return BoundParameter(decl, isRequired: isRequired);
    });
    properties.addAll(boundProperties);

    operations = type.instanceMembers.values
        .where(isOperation)
        .map((decl) => ResourceControllerOperationRuntimeImpl(decl))
        .toList();

    if (conflictingOperations.isNotEmpty) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has ambiguous operations. Offending operating methods: $opNames.");
    }

    if (unsatisfiableOperations.isNotEmpty) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw StateError(
          "Invalid controller. Controller '${type.reflectedType.toString()}' has operations where "
          "parameter is bound with @Bind.path(), but path variable is not declared in @Operation(). Offending operation methods: $opNames");
    }
  }

  final ClassMirror type;

  @override
  List<ResourceControllerOperationRuntimeImpl> operations;

  List<BoundParameter> properties = [];

  List<BoundParameter> parametersForOperation(Operation op) {
    final methodBinder = operations.firstWhere(
        (b) => b.isSuitableForRequest(op.method, op.pathVariables),
        orElse: () => null);

    return [
      properties,
      methodBinder?.positionalParameters ?? [],
      methodBinder?.optionalParameters ?? []
    ].expand((i) => i).toList();
  }

  List<String> get unsatisfiableOperations {
    return operations
        .where((op) {
          final argPathParameters =
              op.positionalParameters.where((p) => p.binding is BoundPath);

          return !argPathParameters
              .every((p) => op.pathVariables.contains(p.name));
        })
        .map((binder) => MirrorSystem.getName(binder.methodSymbol))
        .toList();
  }

  List<String> get conflictingOperations {
    return operations
        .where((op) {
          final possibleConflicts = operations.where((b) => b != op);

          return possibleConflicts.any((opToCompare) {
            if (opToCompare.method != op.method) {
              return false;
            }

            if (opToCompare.pathVariables.length != op.pathVariables.length) {
              return false;
            }

            return opToCompare.pathVariables
                .every((p) => op.pathVariables.contains(p));
          });
        })
        .map((op) => MirrorSystem.getName(op.methodSymbol))
        .toList();
  }

  @override
  void bindProperties(ResourceController rc, Request request, List<String> errorsIn) {
    final mirror = reflect(rc);
    properties.forEach((p) {
      try {
        final value = p.decode(request);
        if (p.isRequired && value == null) {
          errorsIn.add("missing required ${p.binding.type} '${p.name ?? ""}'");
          return;
        }

        mirror.setField(p.symbol, value);
      } on ArgumentError catch (e) {
        errorsIn.add(e.message as String);
      }
    });
  }

  @override
  ResourceControllerOperationRuntime getOperationRuntime(
      String method, List<String> pathVariables) {
    return operations.firstWhere(
        (binder) => binder.isSuitableForRequest(method, pathVariables),
        orElse: () => null);
  }

  // At the end of this method, request.body.decodedData will have been invoked.
//  @override
//  Future<BoundOperation> bind(
//      ResourceController controller, Request request) async {
//    final boundMethod = methodBinderForRequest(request);
//
//    final parseWith = (BoundParameter binder) {
//      var value = binder.decode(request);
//      if (value == null && binder.isRequired) {
//        return BoundValue.error(
//            "missing required ${binder.binding.type} '${binder.name ?? ""}'");
//      }
//
//      return BoundValue(value, symbol: binder.symbol);
//    };
//
//    final initiallyBindWith = (BoundParameter binder) {
//      if (binder.binding is BoundBody ||
//          (binder.binding is BoundQueryParameter &&
//              requestHasFormData(request))) {
//        return BoundValue.deferred(binder, symbol: binder.symbol);
//      }
//
//      return parseWith(binder);
//    };
//
//    final boundProperties = properties.map(initiallyBindWith).toList();
//    final boundPositionalArgs =
//        boundMethod.positionalParameters.map(initiallyBindWith).toList();
//    final boundOptonalArgs =
//        boundMethod.optionalParameters.map(initiallyBindWith).toList();
//    final flattened = [
//      boundProperties,
//      boundPositionalArgs,
//      boundOptonalArgs,
//    ].expand((x) => x).toList();
//
//    var errorMessage = flattened
//        .where((v) => v.errorMessage != null)
//        .map((v) => v.errorMessage)
//        .join(", ");
//
//    if (errorMessage.isNotEmpty) {
//      throw Response.badRequest(body: {"error": errorMessage});
//    }
//
//    if (!request.body.isEmpty) {
//      controller.willDecodeRequestBody(request.body);
//      await request.body.decode();
//      controller.didDecodeRequestBody(request.body);
//    }
//
//    flattened.forEach((boundValue) {
//      if (boundValue.deferredBinder != null) {
//        final output = parseWith(boundValue.deferredBinder);
//        boundValue.value = output.value;
//        boundValue.errorMessage = output.errorMessage;
//      }
//    });
//
//    // Recheck error after deferred
//    errorMessage = flattened
//        .where((v) => v.errorMessage != null)
//        .map((v) => v.errorMessage)
//        .join(", ");
//
//    if (errorMessage.isNotEmpty) {
//      throw Response.badRequest(body: {"error": errorMessage});
//    }
//
//    return BoundOperation()
//      ..methodSymbol = boundMethod.methodSymbol
//      ..positionalMethodArguments =
//          boundPositionalArgs.map((v) => v.value).toList()
//      ..optionalMethodArguments = toSymbolMap(boundOptonalArgs)
//      ..properties = toSymbolMap(boundProperties);
//  }

  @override
  void documentComponents(ResourceController rc, APIDocumentContext context) {
    operations.forEach((b) {
      [b.positionalParameters, b.optionalParameters]
          .expand((b) => b.map((b) => b.binding))
          .whereType<BoundBody>()
          .forEach((b) {
        b.documentComponents(context);
      });
    });
  }

  @override
  List<APIParameter> documentOperationParameters(
      ResourceController rc, APIDocumentContext context, Operation operation) {
    bool usesFormEncodedData = operation.method == "POST" &&
        rc.acceptedContentTypes.any((ct) =>
            ct.primaryType == "application" &&
            ct.subType == "x-www-form-urlencoded");

    return parametersForOperation(operation)
        .map((param) {
          if (param.binding is BoundBody) {
            return null;
          }
          if (usesFormEncodedData && param.binding is BoundQueryParameter) {
            return null;
          }

          return _documentParameter(context, operation, param);
        })
        .where((p) => p != null)
        .toList();
  }

  @override
  APIRequestBody documentOperationRequestBody(
      ResourceController rc, APIDocumentContext context, Operation operation) {
    final binder =
        getOperationRuntime(operation.method, operation.pathVariables)
            as ResourceControllerOperationRuntimeImpl;
    final usesFormEncodedData = operation.method == "POST" &&
        rc.acceptedContentTypes.any((ct) =>
            ct.primaryType == "application" &&
            ct.subType == "x-www-form-urlencoded");
    final boundBody = binder.positionalParameters
            .firstWhere((p) => p.binding is BoundBody, orElse: () => null) ??
        binder.optionalParameters
            .firstWhere((p) => p.binding is BoundBody, orElse: () => null);

    if (boundBody != null) {
      final binding = boundBody.binding as BoundBody;
      final ref = binding.getSchemaObjectReference(context);
      if (ref != null) {
        return APIRequestBody.schema(ref,
            contentTypes: rc.acceptedContentTypes
                .map((ct) => "${ct.primaryType}/${ct.subType}"),
            required: boundBody.isRequired);
      }
    } else if (usesFormEncodedData) {
      final Map<String, APISchemaObject> props =
          parametersForOperation(operation)
              .where((p) => p.binding is BoundQueryParameter)
              .map((param) => _documentParameter(context, operation, param))
              .fold(<String, APISchemaObject>{}, (prev, elem) {
        prev[elem.name] = elem.schema;
        return prev;
      });

      return APIRequestBody.schema(APISchemaObject.object(props),
          contentTypes: ["application/x-www-form-urlencoded"], required: true);
    }

    return null;
  }

  @override
  Map<String, APIOperation> documentOperations(ResourceController rc,
      APIDocumentContext context, String route, APIPath path) {
    final opsForPath = operations
        .where((method) => path.containsPathParameters(method.pathVariables));

    return opsForPath.fold(<String, APIOperation>{}, (prev, method) {
      final instanceMembers = reflect(rc).type.instanceMembers;
      Operation operation =
          firstMetadataOfType(instanceMembers[method.methodSymbol]);

      final operationDoc = APIOperation(
          MirrorSystem.getName(method.methodSymbol),
          rc.documentOperationResponses(context, operation),
          summary: rc.documentOperationSummary(context, operation),
          description: rc.documentOperationDescription(context, operation),
          parameters: rc.documentOperationParameters(context, operation),
          requestBody: rc.documentOperationRequestBody(context, operation),
          tags: rc.documentOperationTags(context, operation));

      if (method.scopes != null) {
        context.defer(() async {
          operationDoc.security?.forEach((sec) {
            sec.requirements.forEach((name, operationScopes) {
              final secType = context.document.components.securitySchemes[name];
              if (secType?.type == APISecuritySchemeType.oauth2 ||
                  secType?.type == APISecuritySchemeType.openID) {
                _mergeScopes(operationScopes, method.scopes);
              }
            });
          });
        });
      }

      prev[method.method.toLowerCase()] = operationDoc;
      return prev;
    });
  }

  void _mergeScopes(
      List<String> operationScopes, List<AuthScope> methodScopes) {
    final existingScopes = operationScopes.map((s) => AuthScope(s)).toList();

    methodScopes.forEach((methodScope) {
      for (var existingScope in existingScopes) {
        if (existingScope.isSubsetOrEqualTo(methodScope)) {
          operationScopes.remove(existingScope.toString());
        }
      }

      operationScopes.add(methodScope.toString());
    });
  }

  APIParameter _documentParameter(
      APIDocumentContext context, Operation operation, BoundParameter param) {
    final schema =
        SerializableRuntimeImpl.documentType(context, param.binding.boundType);
    final documentedParameter = APIParameter(param.name, param.binding.location,
        schema: schema,
        required: param.isRequired,
        allowEmptyValue: schema.type == APIType.boolean);

    return documentedParameter;
  }
}
