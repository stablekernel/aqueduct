import 'package:aqueduct/src/db/managed/managed.dart';

/// Allows storage of unstructured data in a [ManagedObject] property.
///
/// [Document]s may be properties of [ManagedObject] table definition. They are a container
/// for [data] that is a JSON-encodable [Map] or [List]. When storing a [Document] in a database column,
/// [data] is JSON-encoded.
///
/// Use this type to store unstructured or 'schema-less' data. Example:
///
///         class Event extends ManagedObject<_Event> implements _Event {}
///         class _Event {
///           @primaryKey
///           int id;
///
///           String type;
///
///           Document details;
///         }
class Document {
  /// Creates an instance with an optional initial [data].
  ///
  /// If no argument is passed, [data] is null. Otherwise, it is the first argument.
  Document([this.data]);

  /// The JSON-encodable data contained by this instance.
  ///
  /// This value must be JSON-encodable.
  dynamic data;

  /// Returns an element of [data] by index or key.
  ///
  /// [keyOrIndex] may be a [String] or [int].
  ///
  /// When [data] is a [Map], [keyOrIndex] must be a [String] and will return the object for the key
  /// in that map.
  ///
  /// When [data] is a [List], [keyOrIndex] must be a [int] and will return the object at the index
  /// in that list.
  dynamic operator [](dynamic keyOrIndex) {
    return data[keyOrIndex];
  }

  /// Sets an element of [data] by index or key.
  ///
  /// [keyOrIndex] may be a [String] or [int]. [value] must be a JSON-encodable value.
  ///
  /// When [data] is a [Map], [keyOrIndex] must be a [String] and will set [value] for the key
  /// [keyOrIndex].
  ///
  /// When [data] is a [List], [keyOrIndex] must be a [int] and will set [value] for the index
  /// [keyOrIndex]. This index must be within the length of [data]. For all other [List] operations,
  /// you may cast [data] to [List].
  void operator []=(dynamic keyOrIndex, dynamic value) {
    data[keyOrIndex] = value;
  }
}
