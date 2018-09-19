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

    final obj = APISchemaObject.object({})..title = MirrorSystem.getName(mirror.simpleName);
    try {
      for (final property
          in mirror.declarations.values.whereType<VariableMirror>()) {
        final propName = MirrorSystem.getName(property.simpleName);
        obj.properties[propName] = APIComponentDocumenter.documentVariable(context, property);
      }
    } catch (e) {
      obj.additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      obj.description = "Failed to auto-document type '${MirrorSystem.getName(mirror.simpleName)}': ${e.toString()}";
    }

    return obj;
  }

  /// Reads values from [requestBody] into an object.
  ///
  /// This method is invoked when an [ResourceController] property or operation method argument is bound with [Bind.body]. [requestBody] is the
  /// request body of the incoming HTTP request, decoded according to its content-type.
  void readFromMap(Map<String, dynamic> requestBody);

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
