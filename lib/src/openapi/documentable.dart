import 'dart:async';
import 'dart:mirrors';

import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:open_api/v3.dart';

import '../http/serializable.dart';

export 'package:open_api/v3.dart';

abstract class APIComponentDocumenter {
  /// Creates an [APISchemaObject] for a Dart variable.
  ///
  /// [mirror] must reflect on a variable of that has one of the following supported types:
  /// [int], [double], [String], [DateTime], or [HTTPSerializable]. [mirror] may reflect a
  /// [List] if every element of that list is one of the supported types. [mirror] may also reflect
  /// a [Map] if the keys are [String]s and the values are supported types.
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

  void documentComponents(APIDocumentContext context);
}

abstract class APIOperationDocumenter {
  /// Returns all [APIPath] objects this instance knows about.
  Map<String, APIPath> documentPaths(APIDocumentContext context);

  /// Returns all [APIOperation]s this object knows about.
  Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path);
}

class APIDocumentContext {
  APIDocumentContext(APIComponents components)
      : this.components = components,
        schema = new APIComponentCollection<APISchemaObject>._("schemas", components.schemas),
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

  List<Function> _deferredOperations = [];

  void defer(FutureOr document()) {
    _deferredOperations.add(document);
  }

  Future finalize() async {
    final ops = _deferredOperations;
    _deferredOperations = [];
    await Future.forEach(ops, (op) => op());
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
    APIObject obj = reflectClass(T).newInstance(#empty, []).reflectee;
    obj.referenceURI = "#/components/$_typeName/$name";
    return obj;
  }

  T getObjectWithType(Type type) {
    if (_typeReferenceMap.containsKey(type)) {
      return _typeReferenceMap[type];
    }

    APIObject obj = reflectClass(T).newInstance(#empty, []).reflectee;
    obj.referenceURI = "aqueduct-unresolved-reference";

    final completer = _resolutionMap.putIfAbsent(type, () => new Completer<T>.sync());

    completer.future.then((refObject) {
      obj.referenceURI = refObject.referenceURI;
    });

    return obj;
  }
}
