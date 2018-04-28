import 'dart:async';
import 'dart:io';
import 'http.dart';

/// Decodes [bytes] according to [contentType].
///
/// See [RequestBody] for a concrete implementation.
abstract class BodyDecoder {
  BodyDecoder(Stream<List<int>> bodyByteStream)
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
  /// Will throw an error if [bytes] have not been decoded yet.
  Type get decodedType {
    if (!hasBeenDecoded) {
      throw new StateError("Invalid body decoding. Must decode data prior to calling 'decodedType'.");
    }

    return _decodedData.runtimeType;
  }

  final Stream<List<int>> _originalByteStream;
  dynamic _decodedData;
  List<int> _bytes;

  /// Returns decoded data, decoding it if not already decoded.
  ///
  /// This is the raw access method to an HTTP body's decoded value. It is preferable
  /// to use methods such as [decodeAsMap], [decodeAsList], and [decodeAsString], all of which
  /// invoke this method, but throw the appropriate [Response] if they are not the correct type.
  ///
  /// The first time this method is invoked, [bytes] is read in full and decoded according to [contentType].
  /// The decoded data is stored in this instance so that subsequent access will
  /// return the cached decoded data instead of decoding it again.
  ///
  /// If the body is empty, this method will return null and no decoding is attempted.
  ///
  /// The elements of the return value depend on the codec selected from [HTTPCodecRepository], determined
  /// by [contentType]. If there is no codec in [HTTPCodecRepository] for the content type of the
  /// request body being decoded, this method returns the flattened list of bytes directly
  /// from the request body as [List<int>].
  Future<dynamic> get decodedData async {
    if (hasBeenDecoded) {
      return _decodedData;
    }

    final codec = HTTPCodecRepository.defaultInstance
      .codecForContentType(contentType);
    final originalBytes = await _readBytes(bytes);

    if (retainOriginalBytes) {
      _bytes = originalBytes;
    }

    if (codec == null) {
      _decodedData = originalBytes;
      return _decodedData;
    }

    try {
      _decodedData = codec.decoder.convert(originalBytes);
    } on Response {
      rethrow;
    } catch (_) {
      throw new Response.badRequest(body: {"error": "request entity could not be decoded"});
    }

    return _decodedData;
  }

  /// Returns decoded data as [Map], decoding it if not already decoded.
  ///
  /// This method invokes [decodedData] and casts the decoded object as [Map<String, dynamic>].
  ///
  /// If there is no body data, this method returns null.
  ///
  /// If [decodedData] is not a [Map<String, dynamic>] this method throws an
  /// error [Response].
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
  /// If [decodedData] is not a [List] object, this method
  /// throws an error [Response].
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
  /// If [decodedData] is not a [String], this method
  /// throws an error [Response].
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
  /// If decoding has not yet occurred, this method throws an error.
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsMap], but the result is not wrapped in [Future].
  Map<String, dynamic> asMap() {
    if (!hasBeenDecoded) {
      throw new StateError("Invalid body decoding. Body must be decoded before 'asMap' is invoked. Use 'decodeAsMap'.");
    }

    if (_decodedData == null) {
      return null;
    }

    try {
      return _decodedData as Map<String, dynamic>;
    } on CastError {
      throw new Response(422, null, {"error": "unexpected request entity data type"});
    }
  }

  /// Returns decoded data as [List] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an error.
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsList], but the result is not wrapped in [Future].
  List<dynamic> asList() {
    if (!hasBeenDecoded) {
      throw new StateError("Invalid body decoding. Body must be decoded before 'asList' is invoked. Use 'decodeAsList'.");
    }

    if (_decodedData == null) {
      return null;
    }

    try {
      return _decodedData as List<dynamic>;
    } on CastError {
      throw new Response(422, null, {"error": "unexpected request entity data type"});
    }
  }

  /// Returns decoded data as [String] if decoding as already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an error.
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsString], but the result is not wrapped in [Future].
  String asString() {
    if (!hasBeenDecoded) {
      throw new StateError("Invalid body decoding. Body must be decoded before 'asString' is invoked. Use 'decodeAsString'.");
    }

    if (_decodedData == null) {
      return null;
    }

    try {
      return _decodedData as String;
    } on CastError {
      throw new Response(422, null, {"error": "unexpected request entity data type"});
    }
  }

  /// Returns decoded data as a [List] of bytes if decoding has already been attempted.
  ///
  /// If decoding has not yet occurred, this method throws an error.
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsBytes], but the result is not wrapped in [Future].
  List<int> asBytes() {
    if (!hasBeenDecoded) {
      throw new StateError("Invalid body decoding. Body must be decoded before 'asBytes' is invoked. Use 'decodeAsBytes'.");
    }

    if (_bytes != null) {
      return _bytes;
    }

    if (_decodedData == null) {
      return null;
    }

    try {
      return _decodedData as List<int>;
    } on CastError {
      throw new StateError("Invalid body decoding. Body was decoded into another type. Set 'retainOriginalBytes' to true. to retain original bytes.");
    }
  }

  Future<List<int>> _readBytes(Stream<List<int>> stream) async {
    var bytes = await stream.fold(new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));
    return bytes.takeBytes();
  }
}

