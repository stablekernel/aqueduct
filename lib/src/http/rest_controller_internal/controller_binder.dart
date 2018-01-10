import 'dart:async';
import 'dart:mirrors';

import '../response.dart';
import '../rest_controller.dart';
import '../rest_controller_binding.dart';
import '../request.dart';
import 'internal.dart';

class HTTPRequestBinding {
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

class RESTControllerBinder {
  RESTControllerBinder(this.controllerType) {
    var allDeclarations = reflectClass(controllerType).declarations;

    var boundProperties = allDeclarations.values
        .where((decl) => decl is VariableMirror)
        .where((decl) => decl.metadata.any((im) => im.reflectee is Bind))
        .map((decl) {
      var isRequired = allDeclarations[decl.simpleName].metadata.any((im) => im.reflectee is HTTPRequiredParameter);
      return new RESTControllerParameterBinder(decl, isRequired: isRequired);
    });
    propertyBinders.addAll(boundProperties);

    methodBinders = reflectClass(controllerType)
        .instanceMembers
        .values
        .where(isOperation)
        .map((decl) => new RESTControllerMethodBinder(decl))
        .toList();
  }

  Type controllerType;
  List<RESTControllerParameterBinder> propertyBinders = [];

  List<RESTControllerMethodBinder> methodBinders;

  List<String> get unsatisfiableOperations {
    return methodBinders
        .where((binder) {
          final argPathParameters = binder.positionalParameters.where((p) => p.binding is HTTPPath);

          return !argPathParameters.every((p) => binder.pathVariables.contains(p.name));
        })
        .map((binder) => MirrorSystem.getName(binder.methodSymbol))
        .toList();
  }

  List<String> get conflictingOperations {
    return methodBinders
        .where((sourceBinder) {
          final possibleConflicts = methodBinders.where((b) => b != sourceBinder);

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

  RESTControllerMethodBinder methodBinderForRequest(Request req) {
    return methodBinders.firstWhere(
        (binder) => binder.isSuitableForRequest(req.raw.method, req.path.variables.keys.toList()),
        orElse: () => null);
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForPathVariables(Iterable<String> pathVariables) {
    return methodBinders
        .where((binder) => binder.isSuitableForRequest(null, pathVariables.toList()))
        .map((binder) => binder.httpMethod)
        .toList();
  }

  // Used during document generation
  bool hasRequiredBindingsForMethod(MethodMirror mm) {
    if (propertyBinders.any((binder) => binder.isRequired)) {
      return true;
    }

    if (isOperation(mm)) {
      // todo (joeconwaystk): seems like we are creating a duplicate RESTControllerMethodBinder here
      // it likely already exists in methodBinders.
      RESTControllerMethodBinder method = new RESTControllerMethodBinder(mm);
      return method.positionalParameters.any((p) => p.binding is! HTTPPath && p.isRequired);
    }

    return false;
  }

  static Map<Type, RESTControllerBinder> _controllerBinders = {};

  static void addBinder(RESTControllerBinder binder) {
    _controllerBinders[binder.controllerType] = binder;
  }

  static RESTControllerBinder binderForType(Type t) {
    return _controllerBinders[t];
  }

  // At the end of this method, request.body.decodedData will have been invoked.
  static Future<HTTPRequestBinding> bindRequest(RESTController controller, Request request) async {
    var controllerBinder = binderForType(controller.runtimeType);
    var methodBinder = controllerBinder.methodBinderForRequest(request);
    if (methodBinder == null) {
      throw new Response(405,
          {"Allow": controllerBinder.allowedMethodsForPathVariables(request.path.variables.keys).join(", ")}, null);
    }

    var parseWith = (RESTControllerParameterBinder binder) {
      var value = binder.parse(request);
      if (value == null && binder.isRequired) {
        return new HTTPValueBinding.error("Missing ${binder.binding.type} '${binder.name ?? ""}'");
      }

      return new HTTPValueBinding(value, symbol: binder.symbol);
    };

    var initiallyBindWith = (RESTControllerParameterBinder binder) {
      if (binder.binding is HTTPBody || (binder.binding is HTTPQuery && requestHasFormData(request))) {
        return new HTTPValueBinding.deferred(binder, symbol: binder.symbol);
      }

      return parseWith(binder);
    };

    var properties = controllerBinder.propertyBinders.map(initiallyBindWith).toList();
    var positional = methodBinder.positionalParameters.map(initiallyBindWith).toList();
    var optional = methodBinder.optionalParameters.map(initiallyBindWith).toList();
    var flattened = [properties, positional, optional].expand((x) => x).toList();

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

    return new HTTPRequestBinding()
      ..methodSymbol = methodBinder.methodSymbol
      ..positionalMethodArguments = positional.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(optional)
      ..properties = toSymbolMap(properties);
  }
}
