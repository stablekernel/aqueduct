part of aqueduct;

/// Possible values for a delete rule in a [ManagedRelationship].
enum ManagedRelationshipDeleteRule {
  /// Will prevent a delete operation if there is a reference to the would-be deleted object.
  restrict,
  /// All objects with a foreign key reference to the deleted object will also be deleted.
  cascade,
  /// All objects with a foreign key reference to the deleted object will have that reference nullified.
  nullify,
  /// All objects with a foreign key reference to the deleted object will have that reference set to the column's default value.
  setDefault
}

/// A property with this metadata indicates that the entity
///
/// A property with this metadata will be an actual column in the database with a foreign key constraint. Adding this metadata
/// to a property dictates ownership semantics of a relationship. The entity with a property marked with this metadata 'belongs to'
/// the related entity.
class ManagedRelationship {
  const ManagedRelationship(this.inverseKey, {this.onDelete: ManagedRelationshipDeleteRule.nullify, this.isRequired: false});

  /// The symbol for the property in the related entity.
  ///
  /// For example, if a Parent entity has a property named 'children',
  /// the Child entity must have a 'parent' property. The [ManagedRelationship] metadata for the 'parent' property should set
  /// this value to 'children'.
  final Symbol inverseKey;

  /// The delete rule to use when a related instance is deleted.
  ///
  /// For example, if a Parent entity has a property named 'children',
  /// the Child entity must have a 'parent' property (with [ManagedRelationship] metadata). If the Parent is deleted, its 'children' will
  /// be impacted according to this rule. See [ManagedRelationshipDeleteRule] for possible options.
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
  ///
  hasOne,
  hasMany,

  /// A relationship property of this kind will be a foreign key reference to another entity.
  ///
  /// See [ManagedRelationship].
  belongsTo
}

/// Marks a property as a primary key, database type big integer, and autoincrementing. The corresponding property
/// type must be [int].
const ManagedColumnAttributes managedPrimaryKey = const ManagedColumnAttributes(primaryKey: true, databaseType: ManagedPropertyType.bigInteger, autoincrement: true);

/// A declaration annotation for the options on a property in a entity class.
///
/// By default, simply declaring a a property in a entity class will make it a database field
/// and its persistence information will be derived from its type.
/// If, however, the property needs any of the attributes defined by this class, it should be annotated.
class ManagedColumnAttributes {
  /// When true, indicates that this model property is the primary key.
  ///
  /// Only one property of a class may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the adapter will use the appropriate type for Dart type, e.g. a Dart String is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final ManagedPropertyType databaseType;

  /// Indicates whether or not the property can be null or not.
  ///
  /// By default, properties are not nullable.
  final bool isNullable;

  /// The default value of the property.
  ///
  /// By default, a property does not have a default property. This is a String to be interpreted by the adapter. Most
  /// adapters will use this string to further define the type of the database column with a default value, thus it must
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
  /// By default, all properties on a Model are returned if not specified (unless they are to-many relationship properties).
  /// This flag will remove the associated property from the result set unless it is explicitly specified by [resultProperties].
  final bool shouldOmitByDefault;

  /// Indicate to the underlying database to use a serial counter when inserted an instance.
  ///
  /// This is typically used for integer primary keys. In PostgreSQL, for example, an auto-incrementing bigInteger type
  /// will be represented by "bigserial".
  final bool autoincrement;

  /// The metadata constructor.
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
  ManagedColumnAttributes.fromAttributes(ManagedColumnAttributes source, ManagedPropertyType databaseType)
      : this.databaseType = databaseType,
        this.isPrimaryKey = source.isPrimaryKey,
        this.isNullable = source.isNullable,
        this.defaultValue = source.defaultValue,
        this.isUnique = source.isUnique,
        this.isIndexed = source.isIndexed,
        this.shouldOmitByDefault = source.shouldOmitByDefault,
        this.autoincrement = source.autoincrement;
}

/// Metadata for a instance type property that indicates it can be used in [readMap] and [asMap], but is not persisted.
const ManagedTransientAttribute managedTransientAttribute = const ManagedTransientAttribute(availableAsInput: true, availableAsOutput: true);

/// Metadata for a instance type property that indicates it can be used in [readMap], but is not persisted.
const ManagedTransientAttribute managedTransientInputAttribute = const ManagedTransientAttribute(availableAsInput: true, availableAsOutput: false);

/// Metadata for a instance type property that indicates it can be used in [asMap], but is not persisted.
const ManagedTransientAttribute managedTransientOutputAttribute = const ManagedTransientAttribute(availableAsInput: false, availableAsOutput: true);

/// Metadata to associate with a property to indicate it is not a column, but is part of the Model object.
class ManagedTransientAttribute {
  final bool isAvailableAsInput;
  final bool isAvailableAsOutput;
  const ManagedTransientAttribute({bool availableAsInput: true, bool availableAsOutput: true}) :
        isAvailableAsInput = availableAsInput, isAvailableAsOutput = availableAsOutput;
}
