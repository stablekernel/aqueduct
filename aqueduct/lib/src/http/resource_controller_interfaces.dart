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

  void applyRequestProperties(ResourceController untypedController,
      ResourceControllerOperationInvocationArgs args);
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
      ResourceControllerOperationInvocationArgs args) invoker;

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
      @required this.type,
      @required this.defaultValue,
      @required this.acceptFilter,
      @required this.ignoreFilter,
      @required this.requireFilter,
      @required this.rejectFilter})
      : _decoder = decoder;

  // ignore: prefer_constructors_over_static_methods
  static ResourceControllerParameter make<T>(
    {@required String symbolName,
      @required String name,
      @required BindingType location,
      @required bool isRequired,
      @required dynamic Function(dynamic input) decoder,
      @required dynamic defaultValue,
      @required List<String> acceptFilter,
      @required List<String> ignoreFilter,
      @required List<String> requireFilter,
      @required List<String> rejectFilter}) {
    return ResourceControllerParameter(symbolName: symbolName,
      name: name, location: location, isRequired: isRequired,
      decoder: decoder, type: T, defaultValue: defaultValue,
      acceptFilter: acceptFilter, ignoreFilter: ignoreFilter,
      requireFilter: requireFilter, rejectFilter: rejectFilter);
  }


  final String symbolName;
  final String name;
  final Type type;
  final dynamic defaultValue;
  final List<String> acceptFilter;
  final List<String> ignoreFilter;
  final List<String> requireFilter;
  final List<String> rejectFilter;

  /// The location in the request that this parameter is bound to
  final BindingType location;

  final bool isRequired;

  final dynamic Function(dynamic input) _decoder;

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

  dynamic decode(Request request) {
    switch (location) {
      case BindingType.query:
        {
          var queryParameters = request.raw.uri.queryParametersAll;
          var value = request.body.isFormData
              ? request.body.as<Map<String, List<String>>>()[name]
              : queryParameters[name];
          if (value == null) {
            return null;
          }
          return _decoder(value);
        }
        break;

      case BindingType.body:
        {
          if (request.body.isEmpty) {
            return null;
          }
          return _decoder(request.body);
        }
        break;
      case BindingType.header:
        {
          final header = request.raw.headers[name];
          if (header == null) {
            return null;
          }
          return _decoder(header);
        }
        break;

      case BindingType.path:
        {
          final path = request.path.variables[name];
          if (path == null) {
            return null;
          }
          return _decoder(path);
        }
        break;
    }
    return _decoder(request);
  }
}

class ResourceControllerOperationInvocationArgs {
  Map<String, dynamic> instanceVariables;
  Map<String, dynamic> namedArguments;
  List<dynamic> positionalArguments;
}
