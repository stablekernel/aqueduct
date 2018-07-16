import 'dart:async';
import 'dart:io';
import 'dart:mirrors';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

import 'http.dart';

/// Decodes [bytes] according to [contentType].
///
/// See [RequestBody] for a concrete implementation.
abstract class BodyDecoder {
  BodyDecoder(Stream<List<int>> bodyByteStream)
    : _originalByteStream = bodyByteStream;

  /// The stream of bytes to decode.
  ///
  /// This stream is consumed during decoding.
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
  /// By default, invoking [decode] (or one of the methods that invokes it) will discard
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

    return (_decodedData as Object).runtimeType;
  }

  List<int> get originalBytes {
    if (retainOriginalBytes == false) {
      throw StateError("'originalBytes' were not retained. Set 'retainOriginalBytes' to true prior to decoding.");
    }
    return _bytes;
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
  Future<T> decode<T>() async {
    if (hasBeenDecoded) {
      return _cast(_decodedData);
    }

    final codec = HTTPCodecRepository.defaultInstance
      .codecForContentType(contentType);
    final originalBytes = await _readBytes(bytes);

    if (retainOriginalBytes) {
      _bytes = originalBytes;
    }

    if (codec == null) {
      _decodedData = originalBytes;
      return _cast(_decodedData);
    }

    try {
      _decodedData = codec.decoder.convert(originalBytes);
    } on Response {
      rethrow;
    } catch (_) {
      throw new Response.badRequest(body: {"error": "request entity could not be decoded"});
    }

    return _cast(_decodedData);
  }

  T as<T>() {
    if (!hasBeenDecoded) {
      throw StateError("Attempted to access request body without decoding it.");
    }

    return _cast(_decodedData);
  }

  static T _cast<T>(dynamic body) {
    try {
      return runtimeCast(body, reflectType(T)) as T;
    } on CastError {
      throw Response.badRequest(body: {"error": "request entity was unexpected type"});
    }
  }

  Future<List<int>> _readBytes(Stream<List<int>> stream) async {
    var bytes = await stream.fold(new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));
    return bytes.takeBytes();
  }
}

