import 'dart:async';

import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/http/resource_controller.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:meta/meta.dart';

abstract class ResourceControllerRuntime {
  List<ResourceControllerParameter> ivarParameters;
  List<ResourceControllerOperation> operations;

  ResourceControllerDocumenter documenter;

  ResourceControllerOperation getOperationRuntime(
      String method, List<String> pathVariables) {
    return operations.firstWhere(
        (op) => op.isSuitableForRequest(method, pathVariables),
        orElse: () => null);
  }
}

abstract class ResourceControllerDocumenter {
  void documentComponents(ResourceController rc, APIDocumentContext context);

  List<APIParameter> documentOperationParameters(
      ResourceController rc, APIDocumentContext context, Operation operation);

  APIRequestBody documentOperationRequestBody(
      ResourceController rc, APIDocumentContext context, Operation operation);

  Map<String, APIOperation> documentOperations(ResourceController rc,
      APIDocumentContext context, String route, APIPath path);
}

class ResourceControllerOperation {
  ResourceControllerOperation(
      {@required this.scopes,
      @required this.pathVariables,
      @required this.httpMethod,
      @required this.dartMethodName,
      @required this.positionalParameters,
      @required this.namedParameters,
      @required this.invoker});

  final List<AuthScope> scopes;
  final List<String> pathVariables;
  final String httpMethod;
  final String dartMethodName;

  final List<ResourceControllerParameter> positionalParameters;
  final List<ResourceControllerParameter> namedParameters;

  final Future<Response> Function(ResourceController resourceController,
      Request request, ResourceControllerOperationInvocationArgs args) invoker;

  /// Checks if a request's method and path variables will select this binder.
  ///
  /// Note that [requestMethod] may be null; if this is the case, only
  /// path variables are compared.
  bool isSuitableForRequest(
      String requestMethod, List<String> requestPathVariables) {
    if (requestMethod != null && requestMethod.toUpperCase() != httpMethod) {
      return false;
    }

    if (pathVariables.length != requestPathVariables.length) {
      return false;
    }

    return requestPathVariables.every(pathVariables.contains);
  }
}

class ResourceControllerParameter {
  ResourceControllerParameter(
      {@required this.symbolName,
      @required this.name,
      @required this.location,
      @required this.isRequired,
      @required dynamic Function(dynamic input) decoder,
      @required this.type})
      : _decoder = decoder;

  final String symbolName;
  final String name;
  final Type type;

  APIParameterLocation get apiLocation {
    switch (location) {
      case BindingType.body:
        throw StateError('body parameters do not have a location');
      case BindingType.header:
        return APIParameterLocation.header;
      case BindingType.query:
        return APIParameterLocation.query;
      case BindingType.path:
        return APIParameterLocation.path;
    }
    throw StateError('unknown location');
  }

  /// The location in the request that this parameter is bound to
  final BindingType location;

  String get locationName {
    switch (location) {
      case BindingType.query:
        return "query";
      case BindingType.body:
        return "body";
      case BindingType.header:
        return "header";
      case BindingType.path:
        return "path";
    }
    throw StateError('invalid location');
  }

  final bool isRequired;

  final dynamic Function(dynamic input) _decoder;

  dynamic decode(Request request) {
    switch (location) {
      case BindingType.query:
        {
          var queryParameters = request.raw.uri.queryParametersAll;
          var value = queryParameters[name];
          if (value == null) {
            if (request.body.isFormData) {
              value = request.body.as<Map<String, List<String>>>()[name];
            }
          }
          return _decoder(value);
        }
        break;

      case BindingType.body:
        return _decoder(request.body);
      case BindingType.header:
        return _decoder(request.raw.headers[name]);
      case BindingType.path:
        return _decoder(request.path.variables[name]);
    }
    return _decoder(request);
  }
}

class ResourceControllerOperationInvocationArgs {
  Map<Symbol, dynamic> instanceVariables;
  Map<Symbol, dynamic> namedArguments;
  List<dynamic> positionalArguments;
}
