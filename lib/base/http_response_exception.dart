part of aqueduct;

/// An exception for early-exiting a [RequestHandler] to respond to a request.
///
/// If thrown from a [RequestHandler], a [Response] instance with [statusCode] and [message]
/// is used to respond to the [Request] being processed. The [message] is returned
/// as a value in a JSON Object for the key 'error'.
class HTTPResponseException implements Exception {
  /// Creates an instance of a [HTTPResponseException].
  HTTPResponseException(this.statusCode, this.message);

  /// The message to return to the client.
  ///
  /// This message will be JSON encoded in a Map for the key 'error'.
  String message;

  /// The status code of the [Response].
  int statusCode;

  /// A [Response] object derived from this exception.
  Response response() {
    return new Response(statusCode, {HttpHeaders.CONTENT_TYPE: ContentType.JSON}, {"error": message});
  }
}
