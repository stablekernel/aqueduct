import 'dart:mirrors';

import 'package:aqueduct/src/openapi/openapi.dart';

import 'http.dart';

/// Interface for serializable instances to be decoded from an HTTP request body and encoded to an HTTP response body.
///
/// Implementers of this interface may be a [Response.body] and bound with an [Bind.body] in [ResourceController].
abstract class Serializable {
  /// Documents [serializable].
  ///
  /// [serializable] must implement, extend or mixin [Serializable]. The returned [APISchemaObject]
  /// will be of type 'object'. Each instance variable declared in [serializable] will be a property of this object.
  /// Instance variables are documented according to [APIComponentDocumenter.documentVariable]. See the API reference
  /// for this method for supported types.
  ///
  /// You may override the default behavior: f [serializable] implements a static [document] method
  /// with the same signature of this method, the 'overridden' will be invoked instead of the default behavior.
  static APISchemaObject document(
      APIDocumentContext context, Type serializable) {
    final mirror = reflectClass(serializable);
    if (!mirror.isAssignableTo(reflectType(Serializable))) {
      throw ArgumentError(
          "Cannot document '${MirrorSystem.getName(mirror.simpleName)}' as 'Serializable', because it is not an 'Serializable'.");
    }

    final overridden = mirror.staticMembers[#document];
    if (overridden != null) {
      final isValidInvocation = overridden.returnType.isAssignableTo(reflectType(APISchemaObject)) &&
        overridden.parameters.length == 2 &&
        overridden.parameters.first.type
          .isAssignableTo(reflectType(APIDocumentContext)) &&
        overridden.parameters.last.type.isAssignableTo(reflectType(Type));

      if (isValidInvocation) {
        return mirror.invoke(#document, [context, serializable]).reflectee as APISchemaObject;
      } else {
        throw StateError("Type '$serializable' provides static method 'document', "
          "but does not have same signature as 'Serializable.document'.");
      }
    }

    String failureReason;
    final properties = <String, APISchemaObject>{};
    try {
      for (final property
          in mirror.declarations.values.whereType<VariableMirror>()) {
        properties[MirrorSystem.getName(property.simpleName)] =
            APIComponentDocumenter.documentVariable(context, property);
      }
    } catch (e) {
      failureReason = e.toString();
    }

    final obj = APISchemaObject.object(properties);
    if (failureReason != null) {
      obj.additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      obj.description = "Failed to auto-document type '${MirrorSystem.getName(mirror.simpleName)}': $failureReason";
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
