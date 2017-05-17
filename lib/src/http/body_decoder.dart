import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'http.dart';

/// Instances of this class decode HTTP request bodies according to their content type.
///
/// Every instance of [Request] has a [Request.body] property of this type. [HTTPController]s automatically decode
/// [Request.body] prior to invoking a responder method. Other [RequestController]s should use [decodedData]
/// or one of the typed methods ([asList], [asMap], [decodeAsMap], [decodeAsList]) to decode HTTP body data.
///
/// Default decoders are available for 'application/json', 'application/x-www-form-urlencoded' and 'text/*' content types.
class HTTPRequestBody {
  /// Creates a new instance of this type.
  ///
  /// Instances of this type decode [request]'s body based on its content-type.
  ///
  /// See [HTTPCodecRepository] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  HTTPRequestBody(HttpRequest request) : this._request = request {
    _hasContent = (request.headers.contentLength ?? 0) > 0
               || request.headers.chunkedTransferEncoding;
  }

  final HttpRequest _request;
  dynamic _decodedData;

  /// Whether or not the data has been decoded yet.
  ///
  /// True when data has already been decoded.
  ///
  /// If this body has no content, this value is true.
  bool get hasBeenDecoded => _decodedData != null || isEmpty;

  /// Whether or not this body is empty or not.
  ///
  /// If content-length header is greater than 0.
  bool get isEmpty => !_hasContent;
  bool _hasContent;

  /// Returns decoded data, decoding it if not already decoded.
  ///
  /// This is the raw access method to a request body's decoded data. It is preferable
  /// to use methods such as [decodeAsMap], [decodeAsList], and [decodeAsString], all of which
  /// invoke this method.
  ///
  /// The first time this method is invoked, this instance's contents are
  /// read in full and decoded according to the content-type of its request. The decoded data
  /// is stored in this instance so that subsequent access will
  /// return the cached decoded data instead of decoding it again.
  ///
  /// If the body of the request is empty, this method will return null and no decoding is attempted.
  ///
  /// The return type of this method depends on the codec selected from [HTTPCodecRepository], determined
  /// by the content-type of the request.
  ///
  /// If there is no codec in [HTTPCodecRepository] for the content type of the
  /// request body being decoded, this method returns the unaltered list of bytes directly
  /// from the request body as [List<int>].
  ///
  /// If the selected codec produces [String] data (for example, any `text` content-type), the return value
  /// of this method is a [List<String>]. The entire decoded request body is obtained by concatenating
  /// each element of this list. It is preferable to use [decodeAsString] which automatically does this concatenation.
  ///
  /// For `application/json` and `application/x-www-form-urlencoded` data, the return value is a [List<Object>] that contains
  /// exactly one object - the decoded JSON or form object. Prefer to use [decodeAsMap] or [decodeAsList], which returns
  /// the single object from this list. Note that if the request body is a JSON list, the return value of this type
  /// is [List<List<Map<String, dynamic>>>], where the outer list contains exactly one object: the decoded JSON list.
  ///
  /// For custom codecs, the return type of this method is determined by the output of that codec. Note that
  /// the reason [String] data must be concatenated is that body data may be chunked and each chunk is decoded independently.
  /// Whereas a JSON or form data must be read in full before the conversion is complete and so its codec only emits a single,
  /// complete object.
  Future<List<dynamic>> get decodedData async {
    // Note that gzip decompression will automatically be applied by dart:io.
    if (!hasBeenDecoded) {
      if (_decodedData == null) {
        if (_request.headers.contentType != null) {
          var codec = HTTPCodecRepository.defaultInstance
              .codecForContentType(_request.headers.contentType);
          if (codec != null) {
            var bodyStream = codec.decoder.bind(_request).handleError((err) {
              throw new HTTPBodyDecoderException("Failed to decode request body.",
                  underlyingException: err);
            });
            _decodedData = await bodyStream.toList();
          } else {
            _decodedData = await _readBytes();
          }
        } else {
          _decodedData = await _readBytes();
        }
      }
    }

    return _decodedData;
  }

  /// Returns decoded data as [Map], decoding it if not already decoded.
  ///
  /// This method invokes [decodedData] and casts the decoded object as [Map<String, dynamic>].
  ///
  /// If there is no body data, this method returns null.
  ///
  /// If [decodedData] does not produce a [List] that contains a single [Map<String, dynamic>] this method throws an
  /// [HTTPBodyDecoderException].
  ///
  /// For a non-[Future] variant, see [asMap].
  Future<Map<String, dynamic>> decodeAsMap() async {
    await decodedData;

    return asMap();
  }

  /// Returns decoded data as [List], decoding it if not already decoded.
  ///
  /// This method invokes [decodedData] and casts the decoded object as a [List].
  /// Note that this method *may not* be used to return a list of decoded bytes, use
  /// [decodeAsBytes] instead.
  ///
  /// If there is no body data, this method returns null.
  ///
  /// If [decodedData] does not produce a [List] that contains a single [List] object, this method
  /// throws an [HTTPBodyDecoderException].
  ///
  /// For a non-[Future] variant, see [asList].
  Future<List<Map<String, dynamic>>> decodeAsList() async {
    await decodedData;

    return asList();
  }

  /// Returns decoded data as [String], decoding it if not already decoded.
  ///
  /// This method invokes [decodedData] and concatenates each [String] element into a single [String].
  /// The concatenated [String] is returned from this method as a [Future].
  ///
  /// If there is no body data, this method returns null.
  ///
  /// If [decodedData] does not produce a [List<String>], this method
  /// throws an [HTTPBodyDecoderException].
  ///
  /// For a non-[Future] variant, see [asString].
  Future<String> decodeAsString() async {
    await decodedData;

    return asString();
  }

  /// Returns decoded data as [List] of bytes, decoding it if not already decoded.
  ///
  /// This method invokes [decodedData] and returns the decoded bytes if the codec
  /// produced a list of bytes.
  ///
  /// If there is no body data, this method returns null.
  ///
  /// For a non-[Future] variant, see [asBytes].
  Future<List<int>> decodeAsBytes() async {
    await decodedData;

    return asBytes();
  }

  /// Returns decoded data as [Map] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsMap], but the result is not wrapped in [Future].
  Map<String, dynamic> asMap() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asMap() invoked, but has not been decoded yet.");
    }

    if (_decodedData == null) {
      return null;
    }

    var d = _decodedData as List<Map<String, dynamic>>;
    if (d.length != 1) {
      throw new HTTPBodyDecoderException("asMap() failed: more than one object in 'decodedData'.");
    }

    var firstObject = d.first;
    if (firstObject is! Map<String, dynamic>) {
      throw new HTTPBodyDecoderException("asMap() invoked on non-Map<String, dynamic> data.");
    }

    return firstObject;
  }

  /// Returns decoded data as [List] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsList], but the result is not wrapped in [Future].
  List<dynamic> asList() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asList() invoked, but has not been decoded yet.");
    }

    if (_decodedData == null) {
      return null;
    }

    var d = _decodedData as List<dynamic>;
    if (d.length != 1) {
      throw new HTTPBodyDecoderException("decodeAsList() failed: more than one object in 'decodedData'.");
    }

    var firstObject = d.first;
    if (firstObject is! List) {
      throw new HTTPBodyDecoderException("asList() invoked on non-List data.");
    }

    return firstObject;
  }

  /// Returns decoded data as [String] if decoding as already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsString], but the result is not wrapped in [Future].
  String asString() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asString() invoked, but has not been decoded yet.");
    }

    if (_decodedData == null) {
      return null;
    }

    var d = _decodedData as List<String>;
    return d.fold(new StringBuffer(), (StringBuffer buf, value) {
      if (value is! String) {
        throw new HTTPBodyDecoderException("asString() failed: non-String data emitted from codec");
      }

      buf.write(value);
      return buf;
    }).toString();
  }

  /// Returns decoded data as a [List] of bytes if decoding as already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsBytes], but the result is not wrapped in [Future].
  List<int> asBytes() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asBytes() invoked, but has not been decoded yet.");
    }

    if (_decodedData == null) {
      return null;
    }

    return _decodedData as List<int>;
  }

  Future<List<int>> _readBytes() async {
    var bytes = await _request.fold(new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));
    return bytes.takeBytes();
  }
}

/// Thrown when [HTTPRequestBody] encounters an exception.
class HTTPBodyDecoderException implements HTTPResponseException {
  HTTPBodyDecoderException(this.message, {this.underlyingException})
      : statusCode = 400;

  final String message;
  final dynamic underlyingException;

  final int statusCode;

  /// A [Response] object derived from this exception.
  Response get response {
    return new Response(statusCode, null, {"error": message})
      ..contentType = ContentType.JSON;
  }

  String toString() {
    return "HTTPBodyDecoderException: $message ${underlyingException == null ? "" : underlyingException}";
  }
}
