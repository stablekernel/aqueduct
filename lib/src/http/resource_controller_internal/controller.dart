import 'dart:async';
import 'dart:mirrors';

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
  factory BoundController(Type controllerType) {
    if (!_controllerBinders.containsKey(controllerType)) {
      _controllerBinders[controllerType] = new BoundController._(controllerType);
    }

    return _controllerBinders[controllerType];
  }

  BoundController._(this.controllerType) {
    final allDeclarations = reflectClass(controllerType).declarations;

    final boundProperties = allDeclarations.values
        .where((decl) => decl is VariableMirror)
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
  }

  Type controllerType;
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
    return methods.firstWhere(
        (binder) => binder.isSuitableForRequest(req.raw.method, req.path.variables.keys.toList()),
        orElse: () => null);
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForPathVariables(Iterable<String> pathVariables) {
    return methods
        .where((binder) => binder.isSuitableForRequest(null, pathVariables.toList()))
        .map((binder) => binder.httpMethod)
        .toList();
  }

  static Map<Type, BoundController> _controllerBinders = {};

  // At the end of this method, request.body.decodedData will have been invoked.
  static Future<BoundOperation> bindRequestToOperation(ResourceController controller, Request request) async {
    final boundController = new BoundController(controller.runtimeType);
    final boundMethod = boundController.methodBinderForRequest(request);
    if (boundMethod == null) {
      throw new Response(405,
          {"Allow": boundController.allowedMethodsForPathVariables(request.path.variables.keys).join(", ")}, null);
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


    final properties = boundController.properties.map(initiallyBindWith).toList();
    final positional = boundMethod.positionalParameters.map(initiallyBindWith).toList();
    final optional = boundMethod.optionalParameters.map(initiallyBindWith).toList();
    final flattened = [
      properties,
      positional,
      optional,
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
      ..positionalMethodArguments = positional.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(optional)
      ..properties = toSymbolMap(properties);
  }
}
