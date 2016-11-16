part of aqueduct;

/// An exception for early-exiting a [RequestController] to respond to a request.
///
/// If thrown from a [RequestController], a [Response] instance with [statusCode] and [message]
/// is used to respond to the [Request] being processed. The [message] is returned
/// as a value in a JSON Object for the key 'error'.
class HTTPResponseException implements Exception {
  /// Creates an instance of a [HTTPResponseException].
  HTTPResponseException(this.statusCode, this.message);

  /// The message to return to the client.
  ///
  /// This message will be JSON encoded in a Map for the key 'error'.
  final String message;

  /// The status code of the [Response].
  final int statusCode;

  /// A [Response] object derived from this exception.
  Response get response => new Response(statusCode, null, {"error": message})..contentType = ContentType.JSON;
}
