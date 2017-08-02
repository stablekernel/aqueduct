import 'dart:async';
import 'dart:io';
import 'http.dart';

/// Decodes [bytes] according to [contentType].
///
/// See [HTTPRequestBody] for a concrete implementation.
abstract class HTTPBodyDecoder {
  HTTPBodyDecoder(Stream<List<int>> bodyByteStream)
    : _originalByteStream = bodyByteStream;

  /// The stream of bytes to decode.
  Stream<List<int>> get bytes => _originalByteStream;

  /// Determines how [bytes] get decoded.
  ///
  /// A decoder is chosen from [HTTPCodecRepository] according to this value.
  ContentType get contentType;

  /// Whether or not [bytes] is empty.
  ///
  /// No decoding will occur if this flag is true.
  ///
  /// Concrete implementations provide an implementation for this method without inspecting
  /// [bytes].
  bool get isEmpty;

  /// Whether or not [bytes] are available as a list after decoding has occurred.
  ///
  /// By default, invoking [decodedData] (or one of the methods that invokes it) will discard
  /// the initial bytes and only keep the decoded value. Setting this flag to false
  /// will keep a copy of the original bytes, accessible through [asBytes].
  bool retainOriginalBytes = false;

  /// Whether or not [bytes] have been decoded yet.
  ///
  /// If [isEmpty] is true, this value is always true.
  bool get hasBeenDecoded => _decodedData != null || isEmpty;

  /// The type of data [bytes] was decoded into.
  ///
  /// Will throw an exception if [bytes] have not been decoded yet.
  Type get decodedType {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("decodedType invoked prior to decoding data");
    }

    return _decodedData.first.runtimeType;
  }

  final Stream<List<int>> _originalByteStream;
  List<dynamic> _decodedData;
  List<int> _bytes;

  /// Returns decoded data, decoding it if not already decoded.
  ///
  /// This is the raw access method to an HTTP body's decoded data. It is preferable
  /// to use methods such as [decodeAsMap], [decodeAsList], and [decodeAsString], all of which
  /// invoke this method.
  ///
  /// The first time this method is invoked, [bytes] is read in full and decoded according to [contentType].
  /// The decoded data is stored in this instance so that subsequent access will
  /// return the cached decoded data instead of decoding it again.
  ///
  /// If the body is empty, this method will return null and no decoding is attempted.
  ///
  /// The elements of the return value depend on the codec selected from [HTTPCodecRepository], determined
  /// by [contentType]. There are effectively three different scenarios:
  ///
  /// If there is no codec in [HTTPCodecRepository] for the content type of the
  /// request body being decoded, this method returns the flattened list of bytes directly
  /// from the request body as [List<int>].
  ///
  /// If the selected codec produces [String] data (for example, any `text` content-type), the return value
  /// is a list of strings that, when concatenated, are the full [String] body. It is preferable to use
  /// [decodeAsString] which automatically does this concatenation.
  ///
  /// For most [contentType]s, the return value is a single element [List] containing the decoded body object. For example,
  /// this method return a [List] with a single [Map] when the body is a JSON object. If the body is a list of JSON objects,
  /// this method returns a [List] with a single [List] element that contains the JSON objects. It is preferable to use
  /// [decodeAsMap] or [decodeAsList] which unboxes the outer [List] returned by this method.
  Future<List<dynamic>> get decodedData async {
    if (!hasBeenDecoded) {
      if (_decodedData == null) {
        if (contentType != null) {
          var codec = HTTPCodecRepository.defaultInstance
              .codecForContentType(contentType);
          if (codec != null) {
            Stream<List<int>> stream = bytes;
            if (retainOriginalBytes) {
              _bytes = await _readBytes(bytes);
              stream = new Stream.fromIterable([_bytes]);
            }

            var bodyStream = codec.decoder.bind(stream).handleError((err) {
              if (err is HTTPBodyDecoderException) {
                throw err;
              }

              throw new HTTPBodyDecoderException("Failed to decode request body.",
                  underlyingException: err);
            });
            _decodedData = await bodyStream.toList();
          } else {
            _decodedData = await _readBytes(bytes);
          }
        } else {
          _decodedData = await _readBytes(bytes);
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

  /// Returns request body as [List] of bytes.
  ///
  /// If there is no body data, this method returns null.
  ///
  /// This method first invokes [decodedData], potentially decoding the request body
  /// if there is a codec in [HTTPCodecRepository] for the content-type of the request.
  ///
  /// If there is not a codec for the content-type of the request, no decoding occurs and this method returns the
  /// list of bytes directly from the request body.
  ///
  /// If the body was decoded with a codec, this method will throw an exception by default because
  /// the raw request body bytes are discarded after decoding succeeds to free up memory. You may set
  /// [retainOriginalBytes] to true prior to decoding to keep a copy of the raw bytes; in which case,
  /// this method will successfully return the request body bytes.
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

    if (_decodedData.length != 1) {
      throw new HTTPBodyDecoderException("decodeAsList() failed: more than one object in 'decodedData'.");
    }

    var firstObject = _decodedData.first;
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

  /// Returns decoded data as a [List] of bytes if decoding has already been attempted.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsBytes], but the result is not wrapped in [Future].
  List<int> asBytes() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asBytes() invoked, but has not been decoded yet.");
    }

    if (_bytes != null) {
      return _bytes;
    }

    if (_decodedData == null) {
      return null;
    }

    if (_decodedData.first is! int) {
      throw new HTTPBodyDecoderException("asBytes() expected list of bytes, instead got List<${_decodedData.first.runtimeType}>");
    }

    return _decodedData as List<int>;
  }

  Future<List<int>> _readBytes(Stream<List<int>> stream) async {
    var bytes = await stream.fold(new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));
    return bytes.takeBytes();
  }
}

/// Thrown when [HTTPRequestBody] encounters an exception.
class HTTPBodyDecoderException extends HTTPResponseException {
  HTTPBodyDecoderException(
      String message,
      {this.underlyingException, int statusCode: 400, bool shouldTerminateSession: false})
        : super(statusCode, message, shouldTerminateSession: shouldTerminateSession);

  final dynamic underlyingException;

  @override
  String toString() {
    return "HTTPBodyDecoderException: $message ${underlyingException == null ? "" : underlyingException}";
  }
}
