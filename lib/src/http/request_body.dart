import 'dart:io';
import 'http.dart';
import 'body_decoder.dart';

/// Instances of this class decode HTTP request bodies according to their content type.
///
/// Every instance of [Request] has a [Request.body] property of this type. [HTTPController]s automatically decode
/// [Request.body] prior to invoking a responder method. Other [RequestController]s should use [decodedData]
/// or one of the typed methods ([asList], [asMap], [decodeAsMap], [decodeAsList]) to decode HTTP body data.
///
/// Default decoders are available for 'application/json', 'application/x-www-form-urlencoded' and 'text/*' content types.
class HTTPRequestBody extends HTTPBodyDecoder {
  /// Creates a new instance of this type.
  ///
  /// Instances of this type decode [request]'s body based on its content-type.
  ///
  /// See [HTTPCodecRepository] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  HTTPRequestBody(HttpRequest request)
      : this._request = request,
        super(request) {
    _hasContent = (request.headers.contentLength ?? 0) > 0
        || request.headers.chunkedTransferEncoding;
  }

  final HttpRequest _request;
  bool _hasContent;

  @override
  ContentType get contentType => _request.headers.contentType;

  @override
  bool get isEmpty => !_hasContent;
}