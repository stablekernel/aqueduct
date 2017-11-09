import 'dart:mirrors';
import 'internal.dart';

class RESTControllerMethodBinder {
  RESTControllerMethodBinder(MethodMirror mirror) {
    httpMethod = methodBindingFrom(mirror);
    methodSymbol = mirror.simpleName;

    positionalParameters = mirror.parameters
        .where((pm) => !pm.isOptional)
        .map((pm) => new RESTControllerParameterBinder(pm, isRequired: true))
        .toList();
    optionalParameters = mirror.parameters
        .where((pm) => pm.isOptional)
        .map((pm) => new RESTControllerParameterBinder(pm, isRequired: false))
        .toList();
  }

  static String generateKey(String httpMethod, int pathArity) {
    return "${httpMethod.toLowerCase()}/$pathArity";
  }

  Symbol methodSymbol;
  HTTPMethod httpMethod;
  List<RESTControllerParameterBinder> positionalParameters = [];
  List<RESTControllerParameterBinder> optionalParameters = [];

  List<RESTControllerParameterBinder> get pathParameters =>
      positionalParameters.where((p) => p.binding is HTTPPath).toList();
}