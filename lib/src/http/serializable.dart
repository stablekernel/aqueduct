/// Interface for serializable instances to be returned as the HTTP response body.
///
/// Implementers of this interface may be the 'body' argument in a [Response].
abstract class HTTPSerializable {
  /// Returns a serialized version of an object.
  ///
  /// Must return a data type that is encodable using the encoder of the [RequestController]. By default,
  /// values are encoded as JSON, therefore, instances of this class must return JSON-encodable data; such as a String, number
  /// boolean or a Map or List containing those values.
  dynamic asSerializable();
}
