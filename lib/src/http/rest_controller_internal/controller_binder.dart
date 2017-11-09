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

    reflectClass(controllerType)
        .instanceMembers
        .values
        .where(isOperation)
        .map((decl) => new RESTControllerMethodBinder(decl))
        .forEach((RESTControllerMethodBinder method) {
      methodBinders.addBinder(method);
    });
  }

  Type controllerType;
  List<RESTControllerParameterBinder> propertyBinders = [];

  // [method][arity] = binder
  MethodArityMap methodBinders = new MethodArityMap();

  RESTControllerMethodBinder methodBinderForRequest(Request req) {
    return methodBinders.getBinder(req.raw.method, req.path.orderedVariableNames.length);
  }

  // Used to respond with 405 when there is no operation method for HTTP method
  List<String> allowedMethodsForArity(int arity) {
    return methodBinders.contents.keys
        .where((key) {
          return methodBinders.contents[key].containsKey(arity);
        })
        .map((key) => key.toUpperCase())
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
      var allowHeaders = {
        "Allow": controllerBinder.allowedMethodsForArity(request.path.variables?.length ?? 0).join(", ")
      };
      throw new InternalControllerException("No operation found", 405, headers: allowHeaders);
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
      throw new InternalControllerException("Missing required values", 400, errorMessage: errorMessage);
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
      throw new InternalControllerException("Missing required values", 400, errorMessage: errorMessage);
    }

    return new HTTPRequestBinding()
      ..methodSymbol = methodBinder.methodSymbol
      ..positionalMethodArguments = positional.map((v) => v.value).toList()
      ..optionalMethodArguments = toSymbolMap(optional)
      ..properties = toSymbolMap(properties);
  }
}

class MethodArityMap {
  Map<String, Map<int, RESTControllerMethodBinder>> contents = {};

  RESTControllerMethodBinder getBinder(String method, int pathArity) {
    final methodMap = contents[method.toLowerCase()];
    if (methodMap == null) {
      return null;
    }

    return methodMap[pathArity];
  }

  void addBinder(RESTControllerMethodBinder binder) {
    final methodMap =
        contents.putIfAbsent(binder.httpMethod.externalName.toLowerCase(), () => <int, RESTControllerMethodBinder>{});
    methodMap[binder.pathParameters.length] = binder;
  }
}
