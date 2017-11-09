import 'http.dart';

/// Interface for serializable instances to be decoded from an HTTP request body and encoded to an HTTP response body.
///
/// Implementers of this interface may be a [Response.body] and bound with an [Bind.body] in [RESTController].
abstract class HTTPSerializable {
  /// Reads values from [requestBody] into an object.
  ///
  /// This method is invoked when an [RESTController] property or operation method argument is bound with [Bind.body]. [requestBody] is the
  /// request body of the incoming HTTP request, decoded according to its content-type.
  void readFromMap(Map<String, dynamic> requestBody);

  /// Returns a serializable version of an object.
  ///
  /// This method returns a [Map<String, dynamic>] where each key is the name of a property in the implementing type.
  /// If a [Response.body]'s type implements this interface, this method is invoked prior to any content-type encoding
  /// performed by the [Response].  A [Response.body] may also be a [List<HTTPSerializable>], for which this method is invoked on
  /// each element in the list.
  Map<String, dynamic> asMap();
}