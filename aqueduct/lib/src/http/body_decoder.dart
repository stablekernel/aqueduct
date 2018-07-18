import 'dart:async';
import 'dart:io';
import 'dart:convert';
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
      throw new StateError("Invalid body decoding. Must decode data prior to calling 'decodedType'.");
    }

    return (_decodedData as Object).runtimeType;
  }

  /// The raw bytes of this request body.
  ///
  /// This value is valid if [retainOriginalBytes] was set to true prior to [decode] being invoked.
  List<int> get originalBytes {
    if (retainOriginalBytes == false) {
      throw StateError("'originalBytes' were not retained. Set 'retainOriginalBytes' to true prior to decoding.");
    }
    return _bytes;
  }

  final Stream<List<int>> _originalByteStream;
  dynamic _decodedData;
  List<int> _bytes;

  /// Decodes this object's bytes as [T].
  ///
  /// This method will select the [Codec] for [contentType] from the [HTTPCodecRepository].
  /// The bytes of this object will be decoded according to that codec. If the codec
  /// produces a value that is not [T], a bad request error [Response] is thrown.
  ///
  /// Performance considerations:
  ///
  /// The decoded value is retained, and subsequent invocations of this method return the
  /// retained value to avoid performing the decoding process again.
  ///
  /// When [T] is a collection type, specifying type parameters can impact performance.
  /// For example, if [T] is `List<String>`, each element of the decoded list is verified
  /// to be an instance of [String]. If [T] is `List<dynamic>`, this check is not performed.
  /// It is the developer's responsibility to ensure the objects in the list are the
  /// expected type.
  Future<T> decode<T>() async {
    if (hasBeenDecoded) {
      return _cast<T>(_decodedData);
    }

    final codec = HTTPCodecRepository.defaultInstance
      .codecForContentType(contentType);
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
      throw new Response.badRequest(body: {"error": "request entity could not be decoded"});
    }

    return _cast<T>(_decodedData);
  }

  /// Returns previously decoded object as [T].
  ///
  /// This method is the synchronous version of [decode]. However, [decode] must have been called
  /// prior to invoking this method.
  T as<T>() {
    if (!hasBeenDecoded) {
      throw StateError("Attempted to access request body without decoding it.");
    }

    return _cast<T>(_decodedData);
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

