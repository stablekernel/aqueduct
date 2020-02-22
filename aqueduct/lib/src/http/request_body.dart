import 'dart:async';
import 'dart:io';

import 'body_decoder.dart';
import 'http.dart';

/// Objects that represent a request body, and can be decoded into Dart objects.
///
/// Every instance of [Request] has a [Request.body] property of this type. Use
/// [decode] to convert the contents of this object into a Dart type (e.g, [Map] or [List]).
///
/// See also [CodecRegistry] for how decoding occurs.
class RequestBody extends BodyDecoder {
  /// Creates a new instance of this type.
  ///
  /// Instances of this type decode [request]'s body based on its content-type.
  ///
  /// See [CodecRegistry] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  RequestBody(HttpRequest request)
      : _request = request,
        _originalByteStream = request,
        super(request);

  /// The maximum size of a request body.
  ///
  /// A request with a body larger than this size will be rejected. Value is in bytes. Defaults to 10MB (1024 * 1024 * 10).
  static int maxSize = 1024 * 1024 * 10;

  final HttpRequest _request;

  bool get _hasContent =>
      _hasContentLength || _request.headers.chunkedTransferEncoding;

  bool get _hasContentLength => (_request.headers.contentLength ?? 0) > 0;

  @override
  Stream<List<int>> get bytes {
    // If content-length is specified, then we can check it for maxSize
    // and just return the original stream.
    if (_hasContentLength) {
      if (_request.headers.contentLength > maxSize) {
        throw Response(HttpStatus.requestEntityTooLarge, null,
            {"error": "entity length exceeds maximum"});
      }

      return _originalByteStream;
    }

    // If content-length is not specified (e.g., chunked),
    // then we need to check how many bytes we've read to ensure we haven't
    // crossed maxSize
    if (_bufferingController == null) {
      _bufferingController = StreamController<List<int>>(sync: true);

      _originalByteStream.listen((chunk) {
        _bytesRead += chunk.length;
        if (_bytesRead > maxSize) {
          _bufferingController.addError(Response(
              HttpStatus.requestEntityTooLarge,
              null,
              {"error": "entity length exceeds maximum"}));
          _bufferingController.close();
          return;
        }

        _bufferingController.add(chunk);
      }, onDone: () {
        _bufferingController.close();
      }, onError: (e, StackTrace st) {
        if (!_bufferingController.isClosed) {
          _bufferingController.addError(e, st);
          _bufferingController.close();
        }
      }, cancelOnError: true);
    }

    return _bufferingController.stream;
  }

  @override
  ContentType get contentType => _request.headers.contentType;

  @override
  bool get isEmpty => !_hasContent;

  bool get isFormData =>
      contentType != null &&
      contentType.primaryType == "application" &&
      contentType.subType == "x-www-form-urlencoded";

  final Stream<List<int>> _originalByteStream;
  StreamController<List<int>> _bufferingController;
  int _bytesRead = 0;
}
