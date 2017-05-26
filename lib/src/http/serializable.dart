import 'http.dart';

/// Interface for serializable instances to be decoded from an HTTP request body and encoded to an HTTP response body.
///
/// Implementers of this interface may be a [Response.body] and bound with an [HTTPBody] in [HTTPController].
abstract class HTTPSerializable {
  /// Reads values from [requestBody] into an object.
  ///
  /// This method is invoked when an [HTTPController] property or responder method argument is bound with [HTTPBody]. [requestBody] is the
  /// request body of the incoming HTTP request, decoded according to its content-type. This is often [Map<String, dynamic>], but is typed to dynamic to
  /// allow for atypical scenarios.
  void fromRequestBody(dynamic requestBody);

  /// Returns a serializable version of an object.
  ///
  /// This method typically returns a [Map<String, dynamic>] where each key is the name of a property in the implementing type.
  /// If a [Response.body]'s type implements this interface, this method is invoked prior to any content-type encoding
  /// performed by the [Response].
  ///
  /// The return type is dynamic to support non-[Map] objects for which the encoder behaves considerably different than a typical
  /// encoder like [JSON]. A [Response.body] may also be a [List<Serializable>], for which this method is invoked on each element in the list.
  dynamic asSerializable();
}
