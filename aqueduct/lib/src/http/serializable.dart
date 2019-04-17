import 'dart:mirrors';

import 'package:aqueduct/src/openapi/openapi.dart';

import 'http.dart';

/// Interface for serializable instances to be decoded from an HTTP request body and encoded to an HTTP response body.
///
/// Implementers of this interface may be a [Response.body] and bound with an [Bind.body] in [ResourceController].
abstract class Serializable {
  /// Returns an [APISchemaObject] describing this object's type.
  ///
  /// The returned [APISchemaObject] will be of type [APIType.object]. By default, each instance variable
  /// of the receiver's type will be a property of the return value. These variables are documented
  /// with [APIComponentDocumenter.documentVariable]. See the API reference
  /// for this method for supported types.
  APISchemaObject documentSchema(APIDocumentContext context) {
    final mirror = reflect(this).type;

    final obj = APISchemaObject.object({})
      ..title = MirrorSystem.getName(mirror.simpleName);
    try {
      for (final property
          in mirror.declarations.values.whereType<VariableMirror>()) {
        final propName = MirrorSystem.getName(property.simpleName);
        obj.properties[propName] =
            APIComponentDocumenter.documentVariable(context, property);
      }
    } catch (e) {
      obj.additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      obj.description =
          "Failed to auto-document type '${MirrorSystem.getName(mirror.simpleName)}': ${e.toString()}";
    }

    return obj;
  }

  /// Reads values from [object].
  ///
  /// Use [read] instead of this method. [read] applies filters
  /// to [object] before calling this method.
  ///
  /// This method is used by implementors to assign and use values from [object] for its own
  /// purposes. [SerializableException]s should be thrown when [object] violates a constraint
  /// of the receiver.
  void readFromMap(Map<String, dynamic> object);

  /// Reads values from [object], after applying filters.
  ///
  /// The key name must exactly match the name of the property as defined in the receiver's type.
  /// If [object] contains a key that is unknown to the receiver, an exception is thrown (status code: 400).
  ///
  /// [ignore], [reject] and [require] are filters on [object]'s keys with the following behaviors:
  ///
  /// If [ignore] is set, each value for that key is ignored and their value is discarded.
  /// If [reject] is set, if [object] contains any of these keys, a status code 400 exception is thrown.
  /// If [require] is set, all keys must be present in [object].
  ///
  /// Usage:
  ///     var values = json.decode(await request.body.decode());
  ///     var user = User()
  ///       ..read(values, ignore: ["id"]);
  void read(Map<String, dynamic> object,
      {Iterable<String> ignore,
      Iterable<String> reject,
      Iterable<String> require}) {
    if (ignore == null && reject == null && require == null) {
      readFromMap(object);
      return;
    }

    final copy = Map<String, dynamic>.from(object);
    final stillRequired = require?.toList();
    object.keys.forEach((key) {
      if (reject?.contains(key) ?? false) {
        throw SerializableException(["invalid input key '$key'"]);
      }
      if (ignore?.contains(key) ?? false) {
        copy.remove(key);
      }

      stillRequired?.remove(key);
    });

    if (stillRequired?.isNotEmpty ?? false) {
      throw SerializableException(
          ["missing required input key(s): '${stillRequired.join(", ")}'"]);
    }

    readFromMap(copy);
  }

  /// Returns a serializable version of an object.
  ///
  /// This method returns a [Map<String, dynamic>] where each key is the name of a property in the implementing type.
  /// If a [Response.body]'s type implements this interface, this method is invoked prior to any content-type encoding
  /// performed by the [Response].  A [Response.body] may also be a [List<Serializable>], for which this method is invoked on
  /// each element in the list.
  Map<String, dynamic> asMap();

  /// Whether a subclass will automatically be registered as a schema component automatically.
  ///
  /// Defaults to true. When an instance of this subclass is used in a [ResourceController],
  /// it will automatically be registered as a schema component. Its properties will be reflected
  /// on to create the [APISchemaObject]. If false, you must register a schema for the subclass manually.
  ///
  /// Overriding static methods is not enforced by the Dart compiler - check for typos.
  static bool get shouldAutomaticallyDocument => true;
}

class SerializableException implements HandlerException {
  SerializableException(this.reasons);

  final List<String> reasons;

  @override
  Response get response {
    return Response.badRequest(body: {
      "error": "entity validation failed",
      "reasons": reasons ?? "undefined"
    });
  }

  @override
  String toString() {
    final errorString = response.body["error"] as String;
    final reasons = (response.body["reasons"] as List).join(", ");
    return "$errorString $reasons";
  }
}
