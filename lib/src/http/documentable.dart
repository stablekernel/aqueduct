import 'dart:async';
import 'dart:mirrors';

import 'package:open_api/v3.dart';

import '../auth/auth.dart';
import '../db/managed/managed.dart';
import 'http.dart';

export 'package:open_api/v3.dart';

/// An object that can be documented into a OpenAPI specification.
///
/// Classes that wish to participate in the documentation process should extend or mixin this class. You should
/// always mixin or extend this class instead of implementing it.
///
/// Documentation behavior starts at the root of an application (its [ApplicationChannel]) by invoking [documentAPI].
/// The [ApplicationChannel] will invoke methods from this interface on its [ApplicationChannel.entryPoint]. These methods
/// travel down the object graph formed by a [ApplicationChannel], its [Router], [Controller]s, [AuthServer] and [ManagedObject]s.
///
/// Classes that extend this class will override methods such as [documentPaths] and [documentOperations] if they have the information
/// available to complete those requests. Any method from this interface that a subclasses does not override will automatically
/// be forwarded on to its [documentableChild]. Thus, subclasses should override [documentableChild] to return the 'next' documentable
/// item in their logical flow. For [Controller]s, this will be their 'next' handler.
abstract class APIDocumentable {
  /// Returns the next documentable object in a chain of documentable objects.
  ///
  /// If this instance does not have the information to return a value from the other methods in this interface,
  /// it will forward on that method its child.
  APIDocumentable get documentableChild => null;

  /// Returns an [APIDocument] describing an OpenAPI specification.
  APIDocument documentAPI(Map<String, dynamic> projectSpec) => documentableChild?.documentAPI(projectSpec);

  /// Returns all [APIPath] objects this instance knows about.
  Map<String, APIPath> documentPaths(APIComponentRegistry components) => documentableChild?.documentPaths(components);

  /// Returns all [APIOperation]s this object knows about.
  Map<String, APIOperation> documentOperations(APIComponentRegistry components, APIPath path) =>
      documentableChild?.documentOperations(components, path);

  void documentComponents(APIComponentRegistry components) => documentableChild?.documentComponents(components);
}

class APIComponentRegistry {
  APIComponentRegistry(this.components)
      : schema = new APIComponentRegistryItem<APISchemaObject>._("schemas", components.schemas),
        responses = new APIComponentRegistryItem<APIResponse>._("responses", components.responses),
        parameters = new APIComponentRegistryItem<APIParameter>._("parameters", components.parameters),
        requestBodies = new APIComponentRegistryItem<APIRequestBody>._("requestBodies", components.requestBodies),
        headers = new APIComponentRegistryItem<APIHeader>._("headers", components.headers),
        securitySchemes =
            new APIComponentRegistryItem<APISecurityScheme>._("securitySchemes", components.securitySchemes),
        callbacks = new APIComponentRegistryItem<APICallback>._("callbacks", components.callbacks);

  final APIComponents components;

  final APIComponentRegistryItem<APISchemaObject> schema;
  final APIComponentRegistryItem<APIResponse> responses;
  final APIComponentRegistryItem<APIParameter> parameters;
  final APIComponentRegistryItem<APIRequestBody> requestBodies;
  final APIComponentRegistryItem<APIHeader> headers;
  final APIComponentRegistryItem<APISecurityScheme> securitySchemes;
  final APIComponentRegistryItem<APICallback> callbacks;
}

class APIComponentRegistryItem<T extends APIObject> {
  APIComponentRegistryItem._(this._typeName, this._componentMap);

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
