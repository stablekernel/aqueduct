part of aqueduct_test.client;

/// Instances are HTTP responses returned from [TestClient].
///
/// Instances are created when invoking an execution method with a [TestClient].
///
/// See methods like [expectResponse], [hasResponse] and [hasStatus] for usage.
class TestResponse {
  TestResponse._(this._innerResponse)
    : bodyDecoder = new TestResponseBody(_innerResponse);

  final HttpClientResponse _innerResponse;

  /// HTTP Body of this instance,
  ///
  /// Use this property to retrieve the body of this request. This property behaves exactly like
  /// [Request.body] and is automatically decoded before this instance becomes available.
  final TestResponseBody bodyDecoder;

  /// The HTTP response body decoded according to its Content-Type.
  ///
  /// Prefer to use [bodyDecoder].
  ///
  /// Decoding is performed by [bodyDecoder].
  dynamic get decodedBody {
    if (bodyDecoder.isEmpty) {
      return null;
    }

    if (reflectType(bodyDecoder.decodedType).isSubtypeOf(reflectType(Map))) {
      return bodyDecoder.asMap();
    } else if (reflectType(bodyDecoder.decodedType).isSubtypeOf(reflectType(String))) {
      return bodyDecoder.asString();
    } else if (reflectType(bodyDecoder.decodedType).isSubtypeOf(reflectType(List))) {
      return bodyDecoder.asList();
    }

    return bodyDecoder.asBytes();
  }

  /// A [String] representation of the body.
  ///
  /// Kept for backwards compatibility, use [bodyDecoder] instead.
  String get body {
    if (decodedBody == null) {
      return null;
    }

    var codec = HTTPCodecRepository
        .defaultInstance
        .codecForContentType(_innerResponse.headers.contentType);

    return utf8.decode(codec.encode(decodedBody));
  }

  /// HTTP response headers.
  HttpHeaders get headers => _innerResponse.headers;

  /// The Content-Length of the response if provided.
  int get contentLength => _innerResponse.contentLength;

  /// The status code of the response.
  int get statusCode => _innerResponse.statusCode;

  /// Whether or not the response is a redirect.
  bool get isRedirect => _innerResponse.isRedirect;

  /// The [decodedBody] typed to a [List].
  ///
  /// Use [bodyDecoder] instead.
  List<dynamic> get asList => bodyDecoder.asList();

  /// The [decodedBody] typed to a [Map].
  ///
  /// Use [bodyDecoder] instead.
  Map<dynamic, dynamic> get asMap => decodedBody as Map;

  @override
  String toString() {
    var buffer = new StringBuffer();
    buffer.writeln("-----------\n- Status code is $statusCode");
    buffer.writeln("- Headers are the following:");

    var headerItems = headers.toString().split("\n");
    headerItems.removeWhere((str) => str == "");
    headerItems.forEach((header) {
      buffer.writeln("  - $header");
    });

    if (!bodyDecoder.isEmpty) {
      buffer.writeln(decodedBody.toString());
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
  /// See [HTTPCodecRepository] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  TestResponseBody(HttpClientResponse response)
      : this._response = response,
        super(response) {
    _hasContent = (response.headers.contentLength ?? 0) > 0
        || response.headers.chunkedTransferEncoding;
  }

  final HttpClientResponse _response;
  bool _hasContent;

  @override
  ContentType get contentType => _response.headers.contentType;

  @override
  bool get isEmpty => !_hasContent;
}