import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:open_api/v3.dart';

/// The methods you implement to document OpenAPI components.
///
/// The documentation process calls methods from objects of this type. You implement methods from
/// this interface to add reusable components to your OpenAPI document. You may use these components
/// when documenting other components or when implementing [APIOperationDocumenter].
///
/// You must implement [documentComponents].
///
/// [ApplicationChannel], [Controller], [ManagedEntity], and [AuthServer] all implement this interface.
///
abstract class APIComponentDocumenter {
  /// Creates an [APISchemaObject] from a reflected variable.
  ///
  /// [mirror] must reflect on a variable of that has one of the following supported types:
  /// [int], [double], [String], [DateTime], or [Serializable]. [mirror] may reflect a
  /// [List] if every element of that list is one of the supported types. [mirror] may also reflect
  /// a [Map] if the keys are [String]s and the values are supported types.
  ///
  /// Any documentation comments for the declared variable will available in the returned object.
  static APISchemaObject documentVariable(
      APIDocumentContext context, VariableMirror mirror) {
    APISchemaObject object = documentType(context, mirror.type)
      ..title = MirrorSystem.getName(mirror.simpleName);

    return object;
  }

  /// Creates an [APISchemaObject] from a reflected class.
  ///
  /// [type] must be representable as an [APISchemaObject]. This includes primitive types (int, String, etc.),
  /// maps, lists and any type that implements [Serializable].
  ///
  /// See [Serializable.documentSchema] for details on automatic document generation behavior for these types.
  static APISchemaObject documentType(
      APIDocumentContext context, TypeMirror type) {
    if (type.isAssignableTo(reflectType(int))) {
      return APISchemaObject.integer();
    } else if (type.isAssignableTo(reflectType(double))) {
      return APISchemaObject.number();
    } else if (type.isAssignableTo(reflectType(String))) {
      return APISchemaObject.string();
    } else if (type.isAssignableTo(reflectType(bool))) {
      return APISchemaObject.boolean();
    } else if (type.isAssignableTo(reflectType(DateTime))) {
      return APISchemaObject.string(format: "date-time");
    } else if (type.isAssignableTo(reflectType(List))) {
      return APISchemaObject.array(
          ofSchema: documentType(context, type.typeArguments.first));
    } else if (type.isAssignableTo(reflectType(Map))) {
      if (!type.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw ArgumentError("Unsupported type 'Map' with non-string keys.");
      }
      return APISchemaObject()
        ..type = APIType.object
        ..additionalPropertySchema =
            documentType(context, type.typeArguments.last);
    } else if (type.isAssignableTo(reflectType(Serializable))) {
      final instance = (type as ClassMirror).newInstance(const Symbol(''), []).reflectee as Serializable;
      return instance.documentSchema(context);
    }

    throw ArgumentError(
        "Unsupported type '${MirrorSystem.getName(type.simpleName)}' for 'APIComponentDocumenter.documentType'.");
  }

  /// Tells this object to add its components to [context].
  ///
  /// You may register components with [context] in this method. The order in which components
  /// are registered does not matter.
  ///
  /// Example:
  ///
  ///         class Car implements APIComponentDocumenter {
  ///           @override
  ///           void documentComponents(APIDocumentContext context) {
  ///             context.schema.register("Car", APISchemaObject.object({
  ///               "make": APISchemaObject.string(),
  ///               "model": APISchemaObject.string(),
  ///               "year": APISchemaObject.integer(),
  ///             }));
  ///           }
  ///         }
  ///
  /// See [APIDocumentContext] for more details.
  void documentComponents(APIDocumentContext context);
}

/// The methods you implement to document the operations of a [Controller].
///
/// The documentation process calls these methods for every [Controller] in your [ApplicationChannel].
/// You implement [documentOperations] to create or modify [APIOperation] objects that describe the
/// HTTP operations that a controller handler.
abstract class APIOperationDocumenter {
  /// Tells this object to return all [APIPath]s it handles.
  ///
  /// This method is implemented by [Router] to provide the paths of an OpenAPI document
  /// and typically shouldn't be overridden by another controller.
  Map<String, APIPath> documentPaths(APIDocumentContext context);

  /// Tells this object to return all [APIOperation]s it handles.
  ///
  /// You implement this method to create or modify [APIOperation] objects that describe the
  /// HTTP operations that a controller handles. Each controller in the channel, starting with
  /// the entry point, have this method.
  ///
  /// By default, a controller returns the operations created by its linked controllers.
  ///
  /// Endpoint controllers should override this method to create a [Map] of [APIOperation] objects, where the
  /// key is a [String] representation of the status code the response is for. Example:
  ///
  ///       @override
  ///       Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
  ///         if (path.containsPathParameters(['id'])) {
  ///           return {
  ///             "get": APIOperation("Get one thing", {
  ///               "200": APIResponse(...)
  ///             })
  ///           };
  ///         }
  ///
  ///         return {
  ///           "get": APIOperation("Get some things", {
  ///             "200": APIResponse(...)
  ///           })
  ///         };
  ///       }
  ///
  /// Middleware controllers should override this method to call the superclass' implementation (which gathers
  /// the operation objects from an endpoint controller) and then modify those operations before returning them.
  ///
  ///       @override
  ///       Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
  ///         final ops = super.documentOperation(context, path);
  ///
  ///         // add x-api-key header parameter to each operation
  ///         ops.values.forEach((op) {
  ///           op.addParameter(new APIParameter.header("x-api-key, schema: new APISchemaObject.string()));
  ///         });
  ///
  ///         return ops;
  ///       }
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path);
}

/// An object that contains information about [APIDocument] being generated.
///
/// This object is passed to you in every documentation method. You use this method
/// to work with components and schedule deferred functionality.
///
/// Component registries for each type of component - e.g. [schema], [responses] - are used to
/// register and reference those types.
class APIDocumentContext {
  /// Creates a new context.
  APIDocumentContext(this.document)
      : schema = APIComponentCollection<APISchemaObject>._(
            "schemas", document.components.schemas),
        responses = APIComponentCollection<APIResponse>._(
            "responses", document.components.responses),
        parameters = APIComponentCollection<APIParameter>._(
            "parameters", document.components.parameters),
        requestBodies = APIComponentCollection<APIRequestBody>._(
            "requestBodies", document.components.requestBodies),
        headers = APIComponentCollection<APIHeader>._(
            "headers", document.components.headers),
        securitySchemes = APIComponentCollection<APISecurityScheme>._(
            "securitySchemes", document.components.securitySchemes),
        callbacks = APIComponentCollection<APICallback>._(
            "callbacks", document.components.callbacks);

  /// The document being created.
  final APIDocument document;

  /// Reusable [APISchemaObject] components.
  final APIComponentCollection<APISchemaObject> schema;

  /// Reusable [APIResponse] components.
  final APIComponentCollection<APIResponse> responses;

  /// Reusable [APIParameter] components.
  final APIComponentCollection<APIParameter> parameters;

  /// Reusable [APIRequestBody] components.
  final APIComponentCollection<APIRequestBody> requestBodies;

  /// Reusable [APIHeader] components.
  final APIComponentCollection<APIHeader> headers;

  /// Reusable [APISecurityScheme] components.
  final APIComponentCollection<APISecurityScheme> securitySchemes;

  /// Reusable [APICallback] components.
  final APIComponentCollection<APICallback> callbacks;

  List<Function> _deferredOperations = [];

  /// Allows asynchronous code during documentation.
  ///
  /// Documentation methods are synchronous. Asynchronous methods may be called and awaited on
  /// in [document]. All [document] closures will be executes and awaited on before finishing [document].
  /// These closures are called in the order they were added.
  void defer(FutureOr document()) {
    _deferredOperations.add(document);
  }

  /// Finalizes [document] and returns it as a serializable [Map].
  ///
  /// This method is invoked by the command line tool for creating OpenAPI documents.
  Future<Map<String, dynamic>> finalize() async {
    final ops = _deferredOperations;
    _deferredOperations = [];
    await Future.forEach(ops, (op) => op());

    document.paths.values
        .expand((p) => p.operations.values)
        .where((op) => op.security != null)
        .expand((op) => op.security)
        .forEach((req) {
      req.requirements.forEach((schemeName, scopes) {
        final scheme = document.components.securitySchemes[schemeName];
        if (scheme.type == APISecuritySchemeType.oauth2) {
          scheme.flows.values.forEach((flow) {
            scopes.forEach((scope) {
              if (!flow.scopes.containsKey(scope)) {
                flow.scopes[scope] = "";
              }
            });
          });
        }
      });
    });

    return document.asMap();
  }
}

/// A collection of reusable OpenAPI objects.
///
/// Components of type [T] may be registered and referenced through this object.
class APIComponentCollection<T extends APIObject> {
  APIComponentCollection._(this._typeName, this._componentMap);

  final String _typeName;
  final Map<String, T> _componentMap;
  final Map<Type, T> _typeReferenceMap = {};
  final Map<Type, Completer<T>> _resolutionMap = {};

  /// Adds a [component] for [name] so that it can be referenced later.
  ///
  /// [component] will be stored in the OpenAPI document. The component will be usable
  /// by other objects by its [name].
  ///
  /// If this component is represented by a class, provide it as [representation].
  /// Objects may reference either [name] or [representation] when using a component.
  void register(String name, T component, {Type representation}) {
    if (_componentMap.containsKey(name)) {
      return;
    }

    if (representation != null &&
        _typeReferenceMap.containsKey(representation)) {
      return;
    }

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

  /// Returns a reference object in this collection with [name].
  ///
  /// See [getObject].
  T operator [](String name) => getObject(name);

  /// Returns an object that references a component named [name].
  ///
  /// The returned object is always a reference object; it does not contain
  /// actual values of that object.
  ///
  /// An object is always returned, even if no component named [name] exists.
  /// If after [APIDocumentContext.finalize] is called and no object
  /// has been registered for [name], an error is thrown.
  T getObject(String name) {
    final obj = reflectClass(T).newInstance(#empty, []).reflectee as T;
    obj.referenceURI = Uri(path: "/components/$_typeName/$name");
    return obj;
  }

  /// Returns an object that references a component registered for [type].
  ///
  /// The returned object is always a reference object; it does not
  /// contain actual values.
  ///
  /// An object is always returned, even if no component named has been registered
  /// for [type]. If after [APIDocumentContext.finalize] is called and no object
  /// has been registered for [type], an error is thrown.
  T getObjectWithType(Type type) {
    final obj = reflectClass(T).newInstance(#empty, []).reflectee as T;
    obj.referenceURI = Uri(
        path:
            "/components/$_typeName/aqueduct-typeref:${MirrorSystem.getName(reflectType(type).simpleName)}");

    if (_typeReferenceMap.containsKey(type)) {
      obj.referenceURI = _typeReferenceMap[type].referenceURI;
    } else {
      final completer =
          _resolutionMap.putIfAbsent(type, () => Completer<T>.sync());

      completer.future.then((refObject) {
        obj.referenceURI = refObject.referenceURI;
      });
    }

    return obj;
  }

  /// Whether or not [type] has been registered with [register].
  bool hasRegisteredType(Type type) {
    return _typeReferenceMap.containsKey(type);
  }
}
