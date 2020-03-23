part of aqueduct_test.client;

/// An HTTP response from a test application.
///
/// You receive objects of this type when using an [Agent] to execute test requests.
/// The properties of this object are used in test expectations to ensure the endpoint
/// worked as intended.
///
/// Prefer to use methods like [expectResponse], [hasResponse] and [hasStatus] when
/// validating response properties.
class TestResponse {
  TestResponse._(this._innerResponse) : body = TestResponseBody(_innerResponse);

  final HttpClientResponse _innerResponse;

  /// The HTTP body of the response.
  ///
  /// The body is guaranteed to be decoded prior to accessing it. You do
  /// not need to invoke [TestResponseBody.decode] or any of its asynchronous
  /// decoding methods.
  final TestResponseBody body;
  
  /// HTTP response.
  HttpClientResponse get innerResponse => _innerResponse;

  /// HTTP response headers.
  HttpHeaders get headers => _innerResponse.headers;

  /// The Content-Length of the response if provided.
  int get contentLength => _innerResponse.contentLength;

  /// The status code of the response.
  int get statusCode => _innerResponse.statusCode;

  /// Whether or not the response is a redirect.
  bool get isRedirect => _innerResponse.isRedirect;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln("-----------\n- Status code is $statusCode");
    buffer.writeln("- Headers are the following:");

    final headerItems = headers.toString().split("\n");
    headerItems.removeWhere((str) => str == "");
    headerItems.forEach((header) {
      buffer.writeln("  - $header");
    });

    if (!body.isEmpty) {
      buffer.writeln("Decoded body is:");
      buffer.writeln(body.toString());
    } else {
      buffer.writeln("- Body is empty");
    }
    buffer.writeln("-------------------------");

    return buffer.toString();
  }
}

/// Instances of these type represent the body of a [TestResponse].
class TestResponseBody extends BodyDecoder {
  /// Creates a new instance of this type.
  ///
  /// Instances of this type decode [response]'s body based on its content-type.
  ///
  /// See [CodecRegistry] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  TestResponseBody(HttpClientResponse response)
      : _response = response,
        super(response) {
    _hasContent = (response.headers.contentLength ?? 0) > 0 ||
        response.headers.chunkedTransferEncoding;
  }

  final HttpClientResponse _response;
  bool _hasContent;

  @override
  ContentType get contentType => _response.headers.contentType;

  @override
  bool get isEmpty => !_hasContent;

  @override
  String toString() {
    return as().toString();
  }
}
