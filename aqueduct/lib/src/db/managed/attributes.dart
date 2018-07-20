import '../query/query.dart';
import 'managed.dart';

/// Annotation to configure the table definition of a [ManagedObject].
///
/// Adding this metadata to a table definition (`T` in `ManagedObject<T>`) configures the behavior of the underlying table.
/// For example:
///
///         class User extends ManagedObject<_User> implements _User {}
///
///         @Table(unique: const [#name, #email]);
///         class _User {
///           @primaryKey
///           int id;
///
///           String name;
///           String email;
///         }
class Table {
  /// Annotation for table definition.
  ///
  /// See also [Table.unique].
  const Table({this.uniquePropertySet});

  /// Configures each instance of a table definition to be unique for the combination of [properties].
  ///
  /// Adding this metadata to a table definition requires that all instances of this type
  /// must be unique for the combined properties in [properties]. [properties] must contain symbolic names of
  /// properties declared in the table definition, and those properties must be either attributes
  /// or belongs-to relationship properties. See [Table] for example.
  const Table.unique(List<Symbol> properties)
      : this(uniquePropertySet: properties);

  /// Each instance of the associated table definition is unique for these properties.
  ///
  /// null if not set.
  final List<Symbol> uniquePropertySet;
}

/// Possible values for a delete rule in a [Relate].
enum DeleteRule {
  /// Prevents a delete operation if the would-be deleted [ManagedObject] still has references to this relationship.
  restrict,

  /// All objects with a foreign key reference to the deleted object will also be deleted.
  cascade,

  /// All objects with a foreign key reference to the deleted object will have that reference nullified.
  nullify,

  /// All objects with a foreign key reference to the deleted object will have that reference set to the column's default value.
  setDefault
}

/// Metadata to configure property of [ManagedObject] as a foreign key column.
///
/// A property in a [ManagedObject]'s table definition with this metadata will map to a database column
/// that has a foreign key reference to the related [ManagedObject]. Relationships are made up of two [ManagedObject]s, where each
/// has a property that refers to the other. Only one of those properties may have this metadata. The property with this metadata
/// resolves to a column in the database. The relationship property without this metadata resolves to a row or rows in the database.
class Relate {
  static const Symbol _deferredSymbol = #mdrDeferred;

  /// Creates an instance of this type.
  const Relate(this.inversePropertyName,
      {this.onDelete = DeleteRule.nullify, this.isRequired = false});

  const Relate.deferred(DeleteRule onDelete, {bool isRequired = false})
      : this(_deferredSymbol, onDelete: onDelete, isRequired: isRequired);

  /// The symbol for the property in the related [ManagedObject].
  ///
  /// This value must be the symbol for the property in the related [ManagedObject]. This creates the link between
  /// two sides of a relationship between a [ManagedObject].
  final Symbol inversePropertyName;

  /// The delete rule to use when a related instance is deleted.
  ///
  /// This rule dictates how the database should handle deleting objects that have relationships. See [DeleteRule] for possible options.
  ///
  /// If [isRequired] is true, this value may not be [DeleteRule.nullify]. This value defaults to [DeleteRule.nullify].
  final DeleteRule onDelete;

  /// Whether or not this relationship is required.
  ///
  /// By default, [Relate] properties are not required to support the default value of [onDelete].
  /// By setting this value to true, an instance of this entity cannot be created without a valid value for the relationship property.
  final bool isRequired;

  bool get isDeferred {
    return inversePropertyName == _deferredSymbol;
  }
}

/// Metadata to mark a property as a primary key.
///
/// This is a convenience for primary key, database type big integer, and autoincrementing. The corresponding property
/// type must be [int]. The underlying database indexes and uniques the backing column.
const Column primaryKey = Column(
    primaryKey: true,
    databaseType: ManagedPropertyType.bigInteger,
    autoincrement: true);

/// Metadata to describe the behavior of the underlying database column of a persistent property in [ManagedObject] subclasses.
///
/// By default, declaring a property in a table definition will make it a database column
/// and its database column will be derived from the property's type.
/// If the property needs additional directives - like indexing or uniqueness -  it should be annotated with an instance of this class.
///
///         class User extends ManagedObject<_User> implements _User {}
///         class _User {
///           @primaryKey
///           int id;
///
///           @Column(indexed: true, unique: true)
///           String email;
///         }
class Column {
  /// When true, indicates that this property is the primary key.
  ///
  /// Only one property of a class may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the database column type is inferred from the Dart type of the property, e.g. a Dart [String] is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final ManagedPropertyType databaseType;

  /// Indicates whether or not the property can be null or not.
  ///
  /// By default, properties are not nullable.
  final bool isNullable;

  /// The default value of the property.
  ///
  /// By default, a property does not have a default property. This is a String to be interpreted by the database driver. For example,
  /// a PostgreSQL datetime column that defaults to the current time:
  ///
  ///         class User extends ManagedObject<_User> implements _User {}
  ///         class _User {
  ///           @Column(defaultValue: "now()")
  ///           DateTime createdDate;
  ///
  ///           ...
  ///         }
  final String defaultValue;

  /// Whether or not the property is unique among all instances.
  ///
  /// By default, properties are not unique.
  final bool isUnique;

  /// Whether or not the backing database should generate an index for this property.
  ///
  /// By default, properties are not indexed. Properties that are used often in database queries should be indexed.
  final bool isIndexed;

  /// Whether or not fetching an instance of this type should include this property.
  ///
  /// By default, all properties on a [ManagedObject] are returned if not specified (unless they are has-one or has-many relationship properties).
  /// This flag will remove the associated property from the result set unless it is explicitly specified by [Query.returningProperties].
  final bool shouldOmitByDefault;

  /// Indicate to the underlying database to use a serial counter when inserted an instance.
  ///
  /// This is typically used for integer primary keys. In PostgreSQL, for example, an auto-incrementing bigInteger type
  /// will be represented by "bigserial".
  final bool autoincrement;

  /// Creates an instance of this type.
  ///
  /// [defaultValue] is sent as-is to the database, therefore, if the default value is the integer value 2,
  /// pass the string "2". If the default value is a string, it must also be wrapped in single quotes: "'defaultValue'".
  const Column(
      {bool primaryKey = false,
      ManagedPropertyType databaseType,
      bool nullable = false,
      String defaultValue,
      bool unique = false,
      bool indexed = false,
      bool omitByDefault = false,
      bool autoincrement = false})
      : this.isPrimaryKey = primaryKey,
        this.databaseType = databaseType,
        this.isNullable = nullable,
        this.defaultValue = defaultValue,
        this.isUnique = unique,
        this.isIndexed = indexed,
        this.shouldOmitByDefault = omitByDefault,
        this.autoincrement = autoincrement;
}

/// Annotation for [ManagedObject] properties that allows them to participate in [ManagedObject.asMap] and/or [ManagedObject.readFromMap].
///
/// See constructor.
class Serialize {
  /// See constructor.
  final bool isAvailableAsInput;

  /// See constructor.
  final bool isAvailableAsOutput;

  /// Annotates a [ManagedObject] property so it can be serialized.
  ///
  /// Properties declared in a [ManagedObject] subclass are not included in the result of [ManagedObject.asMap]
  /// and are not read from a [Map] in [ManagedObject.readFromMap]. Adding an instance of this type as an annotation
  /// allows those properties to be read from a map and written to a map.
  ///
  /// If [input] is true, this property can be assigned from a key in a [Map] passed to [ManagedObject.readFromMap].
  ///
  /// If [output] is true, this property will be written to the [Map] returned from [ManagedObject.asMap].
  /// If the value of the property is null, the key is not included in the result of [ManagedObject.asMap].
  ///
  /// Both [input] and [output] default to true.
  const Serialize({bool input = true, bool output = true})
      : isAvailableAsInput = input,
        isAvailableAsOutput = output;
}
