import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/src/auth/auth.dart';
import 'package:logging/logging.dart';

import '../response.dart';
import '../resource_controller.dart';
import '../resource_controller_bindings.dart';
import '../request.dart';
import 'internal.dart';

class BoundOperation {
  Symbol methodSymbol;
  Map<Symbol, dynamic> properties = {};
  List<dynamic> positionalMethodArguments = [];
  Map<Symbol, dynamic> optionalMethodArguments = {};

  Future<Response> invoke(InstanceMirror instance) {
    properties.forEach((sym, value) => instance.setField(sym, value));

    return instance.invoke(methodSymbol, positionalMethodArguments, optionalMethodArguments).reflectee
        as Future<Response>;
  }
}

class BoundController {
  BoundController(this.controllerType) {
    final allDeclarations = reflectClass(controllerType).declarations;

    final boundProperties = allDeclarations.values
        .whereType<VariableMirror>()
        .where((decl) => decl.metadata.any((im) => im.reflectee is Bind))
        .map((decl) {
      var isRequired = allDeclarations[decl.simpleName].metadata.any((im) => im.reflectee is HTTPRequiredParameter);
      return new BoundParameter(decl, isRequired: isRequired);
    });
    properties.addAll(boundProperties);

    methods = reflectClass(controllerType)
        .instanceMembers
        .values
        .where(isOperation)
        .map((decl) => new BoundMethod(decl))
        .toList();

    if (conflictingOperations.length > 0) {
      final opNames = conflictingOperations.map((s) => "'$s'").join(", ");
      throw new StateError("Invalid controller. Controller '${controllerType
        .toString()}' has ambiguous operations. Offending operating methods: $opNames.");
    }

    if (unsatisfiableOperations.length > 0) {
      final opNames = unsatisfiableOperations.map((s) => "'$s'").join(", ");
      throw new StateError("Invalid controller. Controller '${controllerType.toString()}' has operations where "
        "parameter is bound with @Bind.path(), but path variable is not declared in @Operation(). Offending operation methods: $opNames");
    }
  }

  final Type controllerType;
  List<BoundParameter> properties = [];
  List<BoundMethod> methods;

  List<BoundParameter> parametersForOperation(Operation op) {
    final methodBinder =
        methods.firstWhere((b) => b.isSuitableForRequest(op.method, op.pathVariables), orElse: () => null);

    return [properties, methodBinder?.positionalParameters ?? [], methodBinder?.optionalParameters ?? []]
        .expand((i) => i)
        .toList();
  }

  List<String> get unsatisfiableOperations {
    return methods
        .where((binder) {
          final argPathParameters = binder.positionalParameters.where((p) => p.binding is BoundPath);

          return !argPathParameters.every((p) => binder.pathVariables.contains(p.name));
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

            if (comparedBinder.pathVariables.length != sourceBinder.pathVariables.length) {
              return false;
            }

            return comparedBinder.pathVariables.every((p) => sourceBinder.pathVariables.contains(p));
          });
        })
        .map((binder) => MirrorSystem.getName(binder.methodSymbol))
        .toList();
  }

  BoundMethod methodBinderForRequest(Request req) {
    return methods.firstWhere((binder) => binder.isSuitableForRequest(req.raw.method, req.path.variables.keys.toList()),
        orElse: () => null);
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForPathVariables(Iterable<String> pathVariables) {
    return methods
        .where((binder) => binder.isSuitableForRequest(null, pathVariables.toList()))
        .map((binder) => binder.httpMethod)
        .toList();
  }

  // At the end of this method, request.body.decodedData will have been invoked.
  Future<BoundOperation> bind(ResourceController controller, Request request) async {
    final boundMethod = methodBinderForRequest(request);
    if (boundMethod == null) {
      throw new Response(
          405, {"Allow": allowedMethodsForPathVariables(request.path.variables.keys).join(", ")}, null);
    }

    if (boundMethod.scopes != null) {
      if (request.authorization == null) {
        new Logger("aqueduct")
            .warning("'${controller.runtimeType}' must be linked to channel that contains an 'Authorizer', because "
                "it uses 'Scope' annotation for one or more of its operation methods.");
        throw new Response.serverError();
      }

      if (!AuthScope.verify(boundMethod.scopes, request.authorization.scopes)) {
        throw new Response.forbidden(
            body: {"error": "insufficient_scope", "scope": boundMethod.scopes.map((s) => s.toString()).join(" ")});
      }
    }

    final parseWith = (BoundParameter binder) {
      var value = binder.parse(request);
      if (value == null && binder.isRequired) {
        return new BoundValue.error("missing required ${binder.binding.type} '${binder.name ?? ""}'");
      }

      return new BoundValue(value, symbol: binder.symbol);
    };

    final initiallyBindWith = (BoundParameter binder) {
      if (binder.binding is BoundBody || (binder.binding is BoundQueryParameter && requestHasFormData(request))) {
        return new BoundValue.deferred(binder, symbol: binder.symbol);
      }

      return parseWith(binder);
    };

    final boundProperties = properties.map(initiallyBindWith).toList();
    final boundPositionalArgs = boundMethod.positionalParameters.map(initiallyBindWith).toList();
    final boundOptonalArgs = boundMethod.optionalParameters.map(initiallyBindWith).toList();
    final flattened = [
      boundProperties,
      boundPositionalArgs,
      boundOptonalArgs,
    ].expand((x) => x).toList();

    var errorMessage = flattened.where((v) => v.errorMessage != null).map((v) => v.errorMessage).join(", ");

    if (errorMessage.isNotEmpty) {
      throw new Response.badRequest(body: {"error": errorMessage});
    }

    if (!request.body.isEmpty) {
      controller.willDecodeRequestBody(request.body);
      await request.body.decodedData;
      controller.didDecodeRequestBody(request.body);
    }

    flattened.forEach((boundValue) {
      if (boundValue.deferredBinder != null) {
        var output = parseWith(boundValue.deferredBinder);
        boundValue.value = output.value;
        boundValue.errorMessage = output.errorMessage;
      }
    });

    // Recheck error after deferred
    errorMessage = flattened.where((v) => v.errorMessage != null).map((v) => v.errorMessage).join(", ");

    if (errorMessage.isNotEmpty) {
      throw new Response.badRequest(body: {"error": errorMessage});
    }

    return new BoundOperation()
      ..methodSymbol = boundMethod.methodSymbol
      ..positionalMethodArguments = boundPositionalArgs.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(boundOptonalArgs)
      ..properties = toSymbolMap(boundProperties);
  }
}
