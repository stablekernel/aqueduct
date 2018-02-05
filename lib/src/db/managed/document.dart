import 'package:aqueduct/src/db/managed/managed.dart';

/// Allows storage of unstructured data in a [ManagedObject] property.
///
/// [Document]s may be properties of [ManagedObject] persistent types. They are a container
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
  /// Creates an empty instance where [data] is null.
  Document();

  /// Creates a new instance containing [data].
  ///
  /// [data] must be a JSON-encodable [Map] or [List].
  Document.from(this.data);


  /// The JSON-encodable data contained by this instance.
  ///
  /// This value must be JSON-encodable.
  dynamic data;
}