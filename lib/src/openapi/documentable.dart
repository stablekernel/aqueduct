import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:open_api/v3.dart';

/// Implement this interface to add OpenAPI Components to an OpenAPI document.
///
/// Components are reusable elements in an OpenAPI document. Types may register components
/// so that other objects can use them when documenting themselves. These components are registered
/// by implementing [documentComponents].
///
/// [ApplicationChannel], [Controller], [ManagedEntity], and [AuthServer] all implement this interface.
///
/// [documentComponents] is called automatically for all controllers in an application (those that are linked to the channel entry point).
/// This method is also called on any property declarations in [ApplicationChannel] that implement this interface (e.g., a service object
/// instantiated in [ApplicationChannel.prepare] and referenced in [ApplicationChannel.entryPoint]).
///
/// If an [APIComponentDocumenter] is not a controller, or is not declared as a property of [ApplicationChannel],
/// override [documentComponents] in [ApplicationChannel] to invoke the documenter's implementation. You must call the superclass' implementation.
/// Example:
///
///         class Channel extends ApplicationChannel {
///           @override
///           void documentComponents(APIDocumentContext context) {
///             super.documentComponents(context);
///
///             undocumentedService.documentComponents(context);
///           }
abstract class APIComponentDocumenter {
  /// Document a declared variable as an [APISchemaObject] for use in an OpenAPI document.
  ///
  /// [mirror] must reflect on a variable of that has one of the following supported types:
  /// [int], [double], [String], [DateTime], or [HTTPSerializable]. [mirror] may reflect a
  /// [List] if every element of that list is one of the supported types. [mirror] may also reflect
  /// a [Map] if the keys are [String]s and the values are supported types.
  ///
  /// Any documentation comments for the declared variable will available in the returned object.
  static APISchemaObject documentVariable(APIDocumentContext context, VariableMirror mirror) {
    APISchemaObject object = documentType(context, mirror.type);

    if (object != null && mirror.owner is ClassMirror) {
      context.defer(() async {
        final docs = await DocumentedElement.get((mirror.owner as ClassMirror).reflectedType);
        final declDocs = docs[mirror.simpleName];
        object.title = declDocs?.summary;
        object.description = declDocs?.description;
      });
    }

    return object;
  }

  /// Document a class as an [APISchemaObject] for use in an OpenAPI document.
  ///
  /// [type] must be representable as an [APISchemaObject]. This includes primitive types (int, String, etc.),
  /// maps, lists and any type that implements [HTTPSerializable].
  ///
  /// See [HTTPSerializable.document] for details on automatic document generation behavior for these types.
  static APISchemaObject documentType(APIDocumentContext context, ClassMirror type) {
    if (type.isAssignableTo(reflectType(int))) {
      return new APISchemaObject.integer();
    } else if (type.isAssignableTo(reflectType(double))) {
      return new APISchemaObject.number();
    } else if (type.isAssignableTo(reflectType(String))) {
      return new APISchemaObject.string();
    } else if (type.isAssignableTo(reflectType(bool))) {
      return new APISchemaObject.boolean();
    } else if (type.isAssignableTo(reflectType(DateTime))) {
      return new APISchemaObject.string(format: "date-time");
    } else if (type.isAssignableTo(reflectType(List))) {
      return new APISchemaObject.array(ofSchema: documentType(context, type.typeArguments.first));
    } else if (type.isAssignableTo(reflectType(Map))) {
      if (!type.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw new ArgumentError("Unsupported type 'Map' with non-string keys.");
      }
      return new APISchemaObject()
        ..type = APIType.object
        ..additionalProperties = documentType(context, type.typeArguments.last);
    } else if (type.isAssignableTo(reflectType(HTTPSerializable))) {
      return HTTPSerializable.document(context, type.reflectedType);
    }

    throw new ArgumentError(
        "Unsupported type '${MirrorSystem.getName(type.simpleName)}' for 'APIComponentDocumenter.documentType'.");
  }

  /// Register reusable OpenAPI Components.
  ///
  /// Components are reusable OpenAPI objects. Other objects may reference these components instead of
  /// duplicating the code to create them.
  ///
  /// To add a component, you register it with a [context]:
  ///
  ///         @override
  ///         void documentComponents(APIDocumentContext context) {
  ///           context.schema.register("Car", new APISchemaObject.object({
  ///             "make": new APISchemaObject.string(),
  ///             "model": new APISchemaObject.string(),
  ///             "year": new APISchemaObject.integer(),
  ///           }));
  ///         }
  ///
  /// See [APIDocumentContext] for more details.
  void documentComponents(APIDocumentContext context);
}

/// Implement this interface to add OpenAPI Operation documentation to an OpenAPI document.
///
/// Operation documenters provide documentation for the operations in an OpenAPI document by implementing
/// [documentOperations]. [Controller] implements this interface; subclasses should override
/// [documentOperations] to either create [APIOperation]s, or add to or modify to an operation
/// created by another controller.
abstract class APIOperationDocumenter {
  /// Return all [APIPath] objects this instance is responsible for managing.
  ///
  /// This method is implemented by [Router] to provide the paths of an OpenAPI document
  /// and typically shouldn't be overridden by another controller.
  Map<String, APIPath> documentPaths(APIDocumentContext context);

  /// Returns all [APIOperation]s this instance handles.
  ///
  /// The return value of this method must be a map, where each key is a lowercase request method (e.g., 'get', 'post', 'delete').
  /// [context] is used to reference components that other objects have registered.
  ///
  /// Endpoint controllers override this method by returning the operations they support. For example:
  ///
  ///       @override
  ///       Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
  ///         if (path.containsPathParameters(['id'])) {
  ///           return {
  ///             "get": new APIOperation("Get one thing", {
  ///               "200": new APIResponse(...)
  ///             })
  ///           };
  ///         }
  ///
  ///         return {
  ///           "get": new APIOperation("Get some things", {
  ///             "200": new APIResponse(...)
  ///           })
  ///         };
  ///       }
  ///
  /// As shown above, endpoint controllers should check the [path] for any path variables that change the documented operations' behavior.
  ///
  /// Middleware controllers override this method by first calling the superclass' implementation. This allows the linked controller to
  /// provide its operations that this method then modifies. Example:
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
  Map<String, APIOperation> documentOperations(APIDocumentContext context, String route, APIPath path);
}

/// Register and reference OpenAPI components while documenting an application.
///
/// When documenting, a context keeps track of reusable components. [APIComponentDocumenter]s
/// add components to a context, and [APIOperationDocumenter] use them to avoid repeating definitions.
///
/// Components are divided into collections of their type, e.g. [schema], [responses], etc. These [APIComponentCollection]s
/// are used to access and register individual components.
class APIDocumentContext {
  APIDocumentContext(this.document)
      : schema = new APIComponentCollection<APISchemaObject>._("schemas", document.components.schemas),
        responses = new APIComponentCollection<APIResponse>._("responses", document.components.responses),
        parameters = new APIComponentCollection<APIParameter>._("parameters", document.components.parameters),
        requestBodies = new APIComponentCollection<APIRequestBody>._("requestBodies", document.components.requestBodies),
        headers = new APIComponentCollection<APIHeader>._("headers", document.components.headers),
        securitySchemes =
            new APIComponentCollection<APISecurityScheme>._("securitySchemes", document.components.securitySchemes),
        callbacks = new APIComponentCollection<APICallback>._("callbacks", document.components.callbacks);

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
  /// Documentation methods in [APIOperationDocumenter] and [APIOperationDocumenter] are synchronous. If
  /// acquiring some information requires asynchronous execution, wrap that behavior in [document]. Once all objects
  /// have finished documenting, [document] is called. For multiple invocations of this method, [document] is called in the order it was added
  void defer(FutureOr document()) {
    _deferredOperations.add(document);
  }

  /// Verifies all referenced objects and completes all [defer] operations.
  ///
  /// You do not need to call this method.
  Future finalize() async {
    final ops = _deferredOperations;
    _deferredOperations = [];
    await Future.forEach(ops, (op) => op());

    _validateReferences(document.asMap());
  }

  void _validateReferences(Map<String, dynamic> spec) {
    String refUri = spec[r"$ref"];
    if (refUri != null) {
      final resolved = document.components.resolve(new APIObject.reference(refUri));
      if (resolved == null) {
        if (refUri.contains("aqueduct-typeref:")) {
          final segments = refUri.split("/");
          throw new StateError("Unresolved OpenAPI reference. No component was registered in '${segments[2]}' for type '${segments.last.split(":").last}'.");
        }
        throw new StateError("Unresolved OpenAPI reference. No component was registered for '$refUri'.");
      }
    }

    spec.values.forEach((v) {
      if (v is Map) {
        _validateReferences(v);
      }
    });
  }
}

/// A collection of reusable OpenAPI objects.
///
/// Components of type [T] may be registered and referenced through this object.
///
/// See also [APIDocumentContext].
class APIComponentCollection<T extends APIObject> {
  APIComponentCollection._(this._typeName, this._componentMap);

  final String _typeName;
  final Map<String, T> _componentMap;
  final Map<Type, T> _typeReferenceMap = {};
  final Map<Type, Completer<T>> _resolutionMap = {};

  /// Adds a component of type [T].
  ///
  /// [component] will be stored in the OpenAPI document. The component will be usable
  /// by other objects by its [name]. If this component is represented by a Dart type,
  /// provide that type as [representation]. This allows objects to reference
  /// a component by its Dart type, instead of its [name].
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

  /// Returns a reference object in this collection with [name].
  ///
  /// See [getObject].
  T operator [](String name) => getObject(name);

  /// Returns an object that references a component named [name].
  ///
  /// The returned object is always a reference object; it does not contain
  /// actual values.
  ///
  /// An object is always returned, even if no component named [name] exists.
  T getObject(String name) {
    APIObject obj = reflectClass(T).newInstance(#empty, []).reflectee;
    obj.referenceURI = "#/components/$_typeName/$name";
    return obj;
  }

  /// Returns an object that references a component registered for [type].
  ///
  /// The returned object is always a reference object; it does not
  /// contain actual values.
  ///
  /// If [type] is never registered, this reference will be invalid.
  T getObjectWithType(Type type) {
    if (_typeReferenceMap.containsKey(type)) {
      return _typeReferenceMap[type];
    }

    APIObject obj = reflectClass(T).newInstance(#empty, []).reflectee;
    obj.referenceURI = "#/components/$_typeName/aqueduct-typeref:${MirrorSystem.getName(reflectType(type).simpleName)}";

    final completer = _resolutionMap.putIfAbsent(type, () => new Completer<T>.sync());

    completer.future.then((refObject) {
      obj.referenceURI = refObject.referenceURI;
    });

    return obj;
  }
}
