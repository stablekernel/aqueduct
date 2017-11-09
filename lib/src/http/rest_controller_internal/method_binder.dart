import 'dart:mirrors';
import 'internal.dart';

class HTTPControllerMethodBinder {
  HTTPControllerMethodBinder(MethodMirror mirror) {
    httpMethod = methodBindingFrom(mirror);
    methodSymbol = mirror.simpleName;

    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new HTTPControllerParameterBinder(pm, isRequired: true))
        .toList();
    optionalParameters = mirror.parameters
        .where((pm) => pm.isOptional)
        .map((pm) => new HTTPControllerParameterBinder(pm, isRequired: false))
        .toList();
  }

  static String generateKey(String httpMethod, int pathArity) {
    return "${httpMethod.toLowerCase()}/$pathArity";
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<HTTPControllerParameterBinder> positionalParameters = [];
  List<HTTPControllerParameterBinder> optionalParameters = [];

  List<HTTPControllerParameterBinder> get pathParameters =>
      positionalParameters.where((p) => p.binding is HTTPPath).toList();
}