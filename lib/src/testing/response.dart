part of aqueduct.test.client;

/// Instances are HTTP responses returned from [TestClient].
///
/// Instances are created when invoking an execution method with a [TestClient].
///
/// See methods like [expectResponse], [hasResponse] and [hasStatus] for usage.
class TestResponse {
  TestResponse._(this._innerResponse);

  final HttpClientResponse _innerResponse;

  /// The HTTP response body decoded according to its Content-Type.
  ///
  /// For example, if the response has a Content-Type of application/json, this value will be the body decoded
  /// from JSON into a [Map] or [List]. You may also use [asList] and [asMap] for additional typing clues for the analyzer.
  dynamic decodedBody;

  /// The raw HTTP response body.
  String body;

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
  /// This is a convenience for casting [decodedBody] to an expected type as well as type-checking the decoded body.
  List<dynamic> get asList => decodedBody as List;

  /// The [decodedBody] typed to a [Map].
  ///
  /// This is a convenience for casting [decodedBody] to an expected type as well as type-checking the decoded body.
  Map<dynamic, dynamic> get asMap => decodedBody as Map;

  Future _decodeBody() {
    var completer = new Completer();
    _innerResponse.transform(UTF8.decoder).listen((contents) {
      body = contents;

      if (body != null) {
        var contentType = this._innerResponse.headers.contentType;
        if (contentType.primaryType == "application" &&
            contentType.subType == "json") {
          decodedBody = JSON.decode(body);
        } else {
          decodedBody = body;
        }
      }
    }).onDone(() {
      completer.complete();
    });

    return completer.future;
  }

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

    if (body != null) {

    } else {
      buffer.writeln("- Body is empty");
    }
    buffer.writeln("-------------------------");

    return buffer.toString();
  }
}