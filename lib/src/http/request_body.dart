import 'dart:async';
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
        this._originalByteStream = request,
        super(request);

  /// The maximum size of a request body.
  ///
  /// A request with a body larger than this size will be rejected. Defaults to 10MB.
  static int maxSize = 1024 * 1024 * 10;

  final HttpRequest _request;
  bool get _hasContent => _hasContentLength || _request.headers.chunkedTransferEncoding;
  bool get _hasContentLength => (_request.headers.contentLength ?? 0) > 0;

  @override
  Stream<List<int>> get bytes {
    // If content-length is specified, then we can check it for maxSize
    // and just return the original stream.
    if (_hasContentLength) {
      if (_request.headers.contentLength > maxSize) {
        throw new HTTPBodyDecoderException(
            "entity length exceeds maximum",
            statusCode: HttpStatus.REQUEST_ENTITY_TOO_LARGE);
      }

      return _originalByteStream;
    }

    // If content-length is not specified (e.g., chunked),
    // then we need to check how many bytes we've read to ensure we haven't
    // crossed maxSize
    if (_bufferingController == null) {
      _bufferingController = new StreamController<List<int>>(sync: true);

      _originalByteStream.listen((chunk) {
        _bytesRead += chunk.length;
        if (_bytesRead > maxSize) {
          _bufferingController.addError(new HTTPBodyDecoderException(
              "entity length exceeds maximum",
              statusCode: HttpStatus.REQUEST_ENTITY_TOO_LARGE));
          _bufferingController.close();
          return;
        }

        _bufferingController.add(chunk);
      }, onDone: () {
        _bufferingController.close();
      }, onError: (e, st) {
        if (!_bufferingController.isClosed) {
          _bufferingController.addError(e, st);
        }
        _bufferingController.close();
      }, cancelOnError: true);
    }

    return _bufferingController.stream;
  }

  @override
  ContentType get contentType => _request.headers.contentType;

  @override
  bool get isEmpty => !_hasContent;

  final Stream<List<int>> _originalByteStream;
  StreamController<List<int>> _bufferingController;
  int _bytesRead = 0;
}