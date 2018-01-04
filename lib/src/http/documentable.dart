import 'dart:async';
import 'dart:mirrors';

import 'package:open_api/v3.dart';

import '../auth/auth.dart';
import '../db/managed/managed.dart';
import 'http.dart';

export 'package:open_api/v3.dart';

abstract class APIComponentDocumenter {
  void documentComponents(APIDocumentContext context);
}

abstract class APIOperationDocumenter {
  /// Returns all [APIPath] objects this instance knows about.
  Map<String, APIPath> documentPaths(APIDocumentContext context);

  /// Returns all [APIOperation]s this object knows about.
  Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path);
}

class APIDocumentContext {
  APIDocumentContext(this.components)
      : schema = new APIComponentCollection<APISchemaObject>._("schemas", components.schemas),
        responses = new APIComponentCollection<APIResponse>._("responses", components.responses),
        parameters = new APIComponentCollection<APIParameter>._("parameters", components.parameters),
        requestBodies = new APIComponentCollection<APIRequestBody>._("requestBodies", components.requestBodies),
        headers = new APIComponentCollection<APIHeader>._("headers", components.headers),
        securitySchemes =
            new APIComponentCollection<APISecurityScheme>._("securitySchemes", components.securitySchemes),
        callbacks = new APIComponentCollection<APICallback>._("callbacks", components.callbacks);

  final APIComponents components;

  final APIComponentCollection<APISchemaObject> schema;
  final APIComponentCollection<APIResponse> responses;
  final APIComponentCollection<APIParameter> parameters;
  final APIComponentCollection<APIRequestBody> requestBodies;
  final APIComponentCollection<APIHeader> headers;
  final APIComponentCollection<APISecurityScheme> securitySchemes;
  final APIComponentCollection<APICallback> callbacks;

  final List<Function> _deferredOperations = [];

  void defer(void document()) {
    _deferredOperations.add(document);
  }

  void finalize() {
    _deferredOperations.forEach((op) {
      op();
    });
  }
}

class APIComponentCollection<T extends APIObject> {
  APIComponentCollection._(this._typeName, this._componentMap);

  final String _typeName;
  final Map<String, T> _componentMap;
  final Map<Type, T> _typeReferenceMap = {};
  final Map<Type, Completer<T>> _resolutionMap = {};

  void register(String name, T component, {Type representation}) {
    _componentMap[name] = component;

    if (representation != null) {
      final refObject = getObject(name);
      _typeReferenceMap[representation] = refObject;

      if (_resolutionMap.containsKey(representation)) {
        _resolutionMap[representation].complete(refObject);
        _resolutionMap.remove(representation);
      }
    }
  }

  T operator [](String name) => getObject(name);

  T getObject(String name) {
    APIObject obj = reflectClass(T).newInstance(const Symbol(""), []).reflectee;
    obj.referenceURI = "#/components/$_typeName/$name";
    return obj;
  }

  T getObjectWithType(Type type) {
    if (_typeReferenceMap.containsKey(type)) {
      return _typeReferenceMap[type];
    }

    APIObject obj = reflectClass(T).newInstance(const Symbol(""), []).reflectee;
    obj.referenceURI = "aqueduct-unresolved-reference";

    final completer = _resolutionMap.putIfAbsent(type, () => new Completer<T>());

    completer.future.then((refObject) {
      obj.referenceURI = refObject.referenceURI;
    });

    return obj;
  }
}
