import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/http/http.dart';
import 'package:runtime/runtime.dart';

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
  /// A decoder is chosen from [CodecRegistry] according to this value.
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
  /// By default, invoking [decode] will discard
  /// the initial bytes and only keep the decoded value. Setting this flag to true
  /// will keep a copy of the original bytes in [originalBytes].
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
      throw StateError(
          "Invalid body decoding. Must decode data prior to calling 'decodedType'.");
    }

    return (_decodedData as Object).runtimeType;
  }

  /// The raw bytes of this request body.
  ///
  /// This value is valid if [retainOriginalBytes] was set to true prior to [decode] being invoked.
  List<int> get originalBytes {
    if (retainOriginalBytes == false) {
      throw StateError(
          "'originalBytes' were not retained. Set 'retainOriginalBytes' to true prior to decoding.");
    }
    return _bytes;
  }

  final Stream<List<int>> _originalByteStream;
  dynamic _decodedData;
  List<int> _bytes;

  /// Decodes this object's bytes as [T].
  ///
  /// This method will select the [Codec] for [contentType] from the [CodecRegistry].
  /// The bytes of this object will be decoded according to that codec. If the codec
  /// produces a value that is not [T], a bad request error [Response] is thrown.
  ///
  /// [T] must be a primitive type (String, int, double, bool, or a List or Map containing only these types).
  /// An error is not thrown if T is not one of these types, but compiled Aqueduct applications may fail at runtime.
  ///
  /// Performance considerations:
  ///
  /// The decoded value is retained, and subsequent invocations of this method return the
  /// retained value to avoid performing the decoding process again.
  Future<T> decode<T>() async {
    if (hasBeenDecoded) {
      return _cast<T>(_decodedData);
    }

    final codec =
        CodecRegistry.defaultInstance.codecForContentType(contentType);
    final originalBytes = await _readBytes(bytes);

    if (retainOriginalBytes) {
      _bytes = originalBytes;
    }

    if (codec == null) {
      _decodedData = originalBytes;
      return _cast<T>(_decodedData);
    }

    try {
      _decodedData = codec.decoder.convert(originalBytes);
    } on Response {
      rethrow;
    } catch (_) {
      throw Response.badRequest(
          body: {"error": "request entity could not be decoded"});
    }

    return _cast<T>(_decodedData);
  }

  /// Returns previously decoded object as [T].
  ///
  /// This method is the synchronous version of [decode]. However, [decode] must have been called
  /// prior to invoking this method or an error is thrown.
  T as<T>() {
    if (!hasBeenDecoded) {
      throw StateError("Attempted to access request body without decoding it.");
    }

    return _cast<T>(_decodedData);
  }

  T _cast<T>(dynamic body) {
    try {
      return RuntimeContext.current.coerce<T>(body);
    } on TypeCoercionException {
      throw Response.badRequest(
          body: {"error": "request entity was unexpected type"});
    }
  }

  Future<List<int>> _readBytes(Stream<List<int>> stream) async {
    var bytes = await stream.fold(
        BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));
    return bytes.takeBytes();
  }
}
