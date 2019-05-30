import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/app/mirror.dart';
import 'package:aqueduct/src/runtime/app/resource_controller_mirror/internal.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

class BoundOperation {
  Symbol methodSymbol;
  Map<Symbol, dynamic> properties = {};
  List<dynamic> positionalMethodArguments = [];
  Map<Symbol, dynamic> optionalMethodArguments = {};

  Future<Response> invoke(ResourceController instance) {
    final mirror = reflect(instance);
    // ignore: unnecessary_lambdas
    properties.forEach((sym, value) {
      mirror.setField(sym, value);
    });

    return mirror
        .invoke(
            methodSymbol, positionalMethodArguments, optionalMethodArguments)
        .reflectee as Future<Response>;
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

    methods = type.instanceMembers.values
        .where(isOperation)
        .map((decl) => BoundMethod(decl))
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

  List<BoundParameter> properties = [];
  List<BoundMethod> methods;

  List<BoundParameter> parametersForOperation(Operation op) {
    final methodBinder = methods.firstWhere(
        (b) => b.isSuitableForRequest(op.method, op.pathVariables),
        orElse: () => null);

    return [
      properties,
      methodBinder?.positionalParameters ?? [],
      methodBinder?.optionalParameters ?? []
    ].expand((i) => i).toList();
  }

  List<String> get unsatisfiableOperations {
    return methods
        .where((binder) {
          final argPathParameters =
              binder.positionalParameters.where((p) => p.binding is BoundPath);

          return !argPathParameters
              .every((p) => binder.pathVariables.contains(p.name));
        })
        .map((binder) => MirrorSystem.getName(binder.methodSymbol))
        .toList();
  }

  List<String> get conflictingOperations {
    return methods
        .where((sourceBinder) {
          final possibleConflicts = methods.where((b) => b != sourceBinder);

          return possibleConflicts.any((comparedBinder) {
            if (comparedBinder.httpMethod != sourceBinder.httpMethod) {
              return false;
            }

            if (comparedBinder.pathVariables.length !=
                sourceBinder.pathVariables.length) {
              return false;
            }

            return comparedBinder.pathVariables
                .every((p) => sourceBinder.pathVariables.contains(p));
          });
        })
        .map((binder) => MirrorSystem.getName(binder.methodSymbol))
        .toList();
  }

  BoundMethod methodBinderForRequest(Request req) {
    return methods.firstWhere(
        (binder) => binder.isSuitableForRequest(
            req.raw.method, req.path.variables.keys.toList()),
        orElse: () => null);
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForPathVariables(Iterable<String> pathVariables) {
    return methods
        .where((binder) =>
            binder.isSuitableForRequest(null, pathVariables.toList()))
        .map((binder) => binder.httpMethod)
        .toList();
  }

  // At the end of this method, request.body.decodedData will have been invoked.
  @override
  Future<BoundOperation> bind(
      ResourceController controller, Request request) async {
    final boundMethod = methodBinderForRequest(request);
    if (boundMethod == null) {
      throw Response(
          405,
          {
            "Allow": allowedMethodsForPathVariables(request.path.variables.keys)
                .join(", ")
          },
          null);
    }

    if (boundMethod.scopes != null) {
      if (request.authorization == null) {
        Logger("aqueduct").warning(
            "'${controller.runtimeType}' must be linked to channel that contains an 'Authorizer', because "
            "it uses 'Scope' annotation for one or more of its operation methods.");
        throw Response.serverError();
      }

      if (!AuthScope.verify(boundMethod.scopes, request.authorization.scopes)) {
        throw Response.forbidden(body: {
          "error": "insufficient_scope",
          "scope": boundMethod.scopes.map((s) => s.toString()).join(" ")
        });
      }
    }

    final parseWith = (BoundParameter binder) {
      var value = binder.decode(request);
      if (value == null && binder.isRequired) {
        return BoundValue.error(
            "missing required ${binder.binding.type} '${binder.name ?? ""}'");
      }

      return BoundValue(value, symbol: binder.symbol);
    };

    final initiallyBindWith = (BoundParameter binder) {
      if (binder.binding is BoundBody ||
          (binder.binding is BoundQueryParameter &&
              requestHasFormData(request))) {
        return BoundValue.deferred(binder, symbol: binder.symbol);
      }

      return parseWith(binder);
    };

    final boundProperties = properties.map(initiallyBindWith).toList();
    final boundPositionalArgs =
        boundMethod.positionalParameters.map(initiallyBindWith).toList();
    final boundOptonalArgs =
        boundMethod.optionalParameters.map(initiallyBindWith).toList();
    final flattened = [
      boundProperties,
      boundPositionalArgs,
      boundOptonalArgs,
    ].expand((x) => x).toList();

    var errorMessage = flattened
        .where((v) => v.errorMessage != null)
        .map((v) => v.errorMessage)
        .join(", ");

    if (errorMessage.isNotEmpty) {
      throw Response.badRequest(body: {"error": errorMessage});
    }

    if (!request.body.isEmpty) {
      controller.willDecodeRequestBody(request.body);
      await request.body.decode();
      controller.didDecodeRequestBody(request.body);
    }

    flattened.forEach((boundValue) {
      if (boundValue.deferredBinder != null) {
        final output = parseWith(boundValue.deferredBinder);
        boundValue.value = output.value;
        boundValue.errorMessage = output.errorMessage;
      }
    });

    // Recheck error after deferred
    errorMessage = flattened
        .where((v) => v.errorMessage != null)
        .map((v) => v.errorMessage)
        .join(", ");

    if (errorMessage.isNotEmpty) {
      throw Response.badRequest(body: {"error": errorMessage});
    }

    return BoundOperation()
      ..methodSymbol = boundMethod.methodSymbol
      ..positionalMethodArguments =
          boundPositionalArgs.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(boundOptonalArgs)
      ..properties = toSymbolMap(boundProperties);
  }

  @override
  void documentComponents(ResourceController rc, APIDocumentContext context) {
    methods.forEach((b) {
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
    final binder = _boundMethodForOperation(operation);
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
    final operations = methods
        .where((method) => path.containsPathParameters(method.pathVariables));

    return operations.fold(<String, APIOperation>{}, (prev, method) {
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

      prev[method.httpMethod.toLowerCase()] = operationDoc;
      return prev;
    });
  }

  BoundMethod _boundMethodForOperation(Operation operation) {
    return methods.firstWhere((m) {
      if (m.httpMethod != operation.method) {
        return false;
      }

      if (m.pathVariables.length != operation.pathVariables.length) {
        return false;
      }

      if (!operation.pathVariables.every((p) => m.pathVariables.contains(p))) {
        return false;
      }

      return true;
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
