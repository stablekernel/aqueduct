import 'managed.dart';

/// Possible values for a delete rule in a [ManagedRelationship].
enum ManagedRelationshipDeleteRule {
  /// Prevents a delete operation if the would-be deleted [ManagedObject] still has references to this relationship.
  restrict,

  /// All objects with a foreign key reference to the deleted object will also be deleted.
  cascade,

  /// All objects with a foreign key reference to the deleted object will have that reference nullified.
  nullify,

  /// All objects with a foreign key reference to the deleted object will have that reference set to the column's default value.
  setDefault
}

/// Metadata for a [ManagedObject] property that requests the property be backed by a foreign key column in a database.
///
/// A property in a [ManagedObject]'s [ManagedObject.PersistentType] with this metadata will map to a database column
/// that has a foreign key reference to the related [ManagedObject]. Relationships are made up of two [ManagedObject]s, where each
/// has a property that refers to the other. Only one of those properties may have this metadata. The property with this metadata
/// resolves to a column in the database. The relationship property without this metadata resolves to a row or rows in the database.
class ManagedRelationship {
  /// Creates an instance of this type.
  const ManagedRelationship(this.inverseKey,
      {this.onDelete: ManagedRelationshipDeleteRule.nullify,
      this.isRequired: false});

  /// The symbol for the property in the related [ManagedObject].
  ///
  /// This value must be the symbol for the property in the related [ManagedObject]. This creates the link between
  /// two sides of a relationship between a [ManagedObject].
  final Symbol inverseKey;

  /// The delete rule to use when a related instance is deleted.
  ///
  /// This rule dictates how the database should handle deleting objects that have relationships. See [ManagedRelationshipDeleteRule] for possible options.
  ///
  /// If [isRequired] is true, this value may not be [ManagedRelationshipDeleteRule.nullify]. This value defaults to [ManagedRelationshipDeleteRule.nullify].
  final ManagedRelationshipDeleteRule onDelete;

  /// Whether or not this relationship is required.
  ///
  /// By default, [ManagedRelationship] properties are not required to support the default value of [onDelete].
  /// By setting this value to true, an instance of this entity cannot be created without a valid value for the relationship property.
  final bool isRequired;
}

/// The different types of relationships.
enum ManagedRelationshipType {
  /// The relationship property is not backed by a database column, but instead represents a single row in the database.
  hasOne,

  /// The relationship property is not backed by a database column, but instead represents many rows in the database.
  hasMany,

  /// A relationship property of this kind will be a foreign key reference to another entity.
  ///
  /// See [ManagedRelationship].
  belongsTo
}

/// Marks a property as a primary key, database type big integer, and autoincrementing. The corresponding property
/// type must be [int]. It is assumed that the underlying database indexes and uniques the backing column.
const ManagedColumnAttributes managedPrimaryKey = const ManagedColumnAttributes(
    primaryKey: true,
    databaseType: ManagedPropertyType.bigInteger,
    autoincrement: true);

/// Metadata to describe the behavior of the underlying database column of a managed property.
///
/// By default, simply declaring a a property in a persistent type class will make it a database column
/// and its persistence information will be derived from its type.
/// If, however, the property needs any of the attributes defined by this class, it should be annotated with an instance of this class.
class ManagedColumnAttributes {
  /// When true, indicates that this model property is the primary key.
  ///
  /// Only one property of a class may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the [PersistentStore] will use the appropriate type for Dart type, e.g. a Dart String is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final ManagedPropertyType databaseType;

  /// Indicates whether or not the property can be null or not.
  ///
  /// By default, properties are not nullable.
  final bool isNullable;

  /// The default value of the property.
  ///
  /// By default, a property does not have a default property. This is a String to be interpreted by the [PersistentStore]. Most
  /// [PersistentStore]s will use this string to further define the type of the database column with a default value, thus it must
  /// be flexible.
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
  /// By default, all properties on a [ManagedObject] are returned if not specified (unless they are to-many relationship properties).
  /// This flag will remove the associated property from the result set unless it is explicitly specified by [Query.resultProperties].
  final bool shouldOmitByDefault;

  /// Indicate to the underlying database to use a serial counter when inserted an instance.
  ///
  /// This is typically used for integer primary keys. In PostgreSQL, for example, an auto-incrementing bigInteger type
  /// will be represented by "bigserial".
  final bool autoincrement;

  /// Creates an instance of this type.
  const ManagedColumnAttributes(
      {bool primaryKey: false,
      ManagedPropertyType databaseType,
      bool nullable: false,
      String defaultValue,
      bool unique: false,
      bool indexed: false,
      bool omitByDefault: false,
      bool autoincrement: false})
      : this.isPrimaryKey = primaryKey,
        this.databaseType = databaseType,
        this.isNullable = nullable,
        this.defaultValue = defaultValue,
        this.isUnique = unique,
        this.isIndexed = indexed,
        this.shouldOmitByDefault = omitByDefault,
        this.autoincrement = autoincrement;

  /// A supporting constructor to support modifying Attributes.
  ManagedColumnAttributes.fromAttributes(
      ManagedColumnAttributes source, ManagedPropertyType databaseType)
      : this.databaseType = databaseType,
        this.isPrimaryKey = source.isPrimaryKey,
        this.isNullable = source.isNullable,
        this.defaultValue = source.defaultValue,
        this.isUnique = source.isUnique,
        this.isIndexed = source.isIndexed,
        this.shouldOmitByDefault = source.shouldOmitByDefault,
        this.autoincrement = source.autoincrement;
}

/// Metadata for a subclass of [ManagedObject] that allows the property to be used in [ManagedObject.readMap] and [ManagedObject.asMap], but is not persisted in the underlying database.
const ManagedTransientAttribute managedTransientAttribute =
    const ManagedTransientAttribute(
        availableAsInput: true, availableAsOutput: true);

/// Metadata for a subclass of [ManagedObject] that indicates it can be used in [ManagedObject.readMap], but is not persisted in the underlying database.
const ManagedTransientAttribute managedTransientInputAttribute =
    const ManagedTransientAttribute(
        availableAsInput: true, availableAsOutput: false);

/// Metadata for a subclass of [ManagedObject] that indicates it can be used in [ManagedObject.asMap], but is not persisted in the underlying database.
const ManagedTransientAttribute managedTransientOutputAttribute =
    const ManagedTransientAttribute(
        availableAsInput: false, availableAsOutput: true);

/// See [managedTransientAttribute], [managedTransientInputAttribute] and [managedTransientOutputAttribute].
class ManagedTransientAttribute {
  final bool isAvailableAsInput;
  final bool isAvailableAsOutput;
  const ManagedTransientAttribute(
      {bool availableAsInput: true, bool availableAsOutput: true})
      : isAvailableAsInput = availableAsInput,
        isAvailableAsOutput = availableAsOutput;
}


/// Metadata that allows a relationship to be declared in another package.
///
/// Relationship properties declared in a [ManagedObject]'s persistent type can have this metadata.
/// When a relationship property has this metadata, the type of that property must be a plain Dart class
/// that serves as a placeholder for the related [ManagedObject]. The related [ManagedObject]'s
/// persistent type *must extend* the placeholder's type and therefore acquire all of its persistent
/// properties.
///
/// This behavior is useful when declaring a [ManagedObject] in a dependency package,
/// but you wish to retain referential integrity with a [ManagedObject] in the importing package. For example,
/// a package named 'geography' declares a 'Location' managed object with a partial relationship and
/// what a 'LocationOwner' must be:
///
///         class Location extends ManagedObject<_Location> implements _Location {}
///         class _Location {
///           @managedPrimaryKey
///           int id;
///
///           double lat;
///           double lon;
///
///           @managedPartialObject
///           @ManagedRelationship(#locations)
///           LocationOwner owner;
///         }
///
///         // This is a 'partial' managed object
///         class LocationOwner {
///           @managedPrimaryKey
///           int id;
///
///           ManagedSet<Location> locations;
///         }
///
///
/// A package importing the 'geography' package can set up a relationship with a 'Location' by subclassing
/// LocationOwner.
///
///         class User extends ManagedObject<_User> implements _User {}
///         class _User extends LocationOwner {
///           String phoneNumber;
///         }
///
/// The concrete [ManagedObject] will inherit all of the properties of the partial managed object
/// and those properties will be persistent.
const _ManagedPartialObject managedPartialObject = const _ManagedPartialObject();
class _ManagedPartialObject {
  const _ManagedPartialObject();
}