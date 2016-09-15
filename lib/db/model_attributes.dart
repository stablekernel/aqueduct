part of aqueduct;

/// Possible values for a delete rule in a [Relationship]
///
/// * [restrict] will prevent a delete operation if there is a reference to the would-be deleted object.
/// * [cascade] will delete all objects with references to this relationship.
/// * [nullify] will nullify the relationship from the related object.
/// * [setDefault] will set the relationship to its default value (if one exists) upon deletion.
enum RelationshipDeleteRule {
  restrict,
  cascade,
  nullify,
  setDefault
}

class RelationshipInverse {
  const RelationshipInverse(this.inverseKey, {this.onDelete: RelationshipDeleteRule.nullify, this.isRequired: false});

  final Symbol inverseKey;
  final RelationshipDeleteRule onDelete;
  final bool isRequired;
}

/// The different types of relationships.
///
/// In SQL terminology, the model with the [belongsTo] relationship will hold the foreign key to the inverse relationship.
/// * [hasOne] prevents the relationship from having more than one foreign key reference.
/// * [hasMany] establishes a to-many relationship to the related model.
/// * [belongsTo] is the inverse of [hasOne] and [hasMany].
enum RelationshipType {
  hasOne,
  hasMany,
  belongsTo // foreign key goes on this entity
}

/// Marks a property as a primary key, database type big integer, and autoincrementing. The corresponding property
/// type must be [int].
const AttributeHint primaryKey = const AttributeHint(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true);

/// A declaration annotation for the options on a property in a entity class.
///
/// By default, simply declaring a a property in a entity class will make it a database field
/// and its persistence information will be derived from its type.
/// If, however, the property needs any of the attributes defined by this class, it should be annotated.
class AttributeHint {
  /// When true, indicates that this model property is the primary key.
  ///
  /// Only one property of a class may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the adapter will use the appropriate type for Dart type, e.g. a Dart String is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final PropertyType databaseType;

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
  const AttributeHint(
      {bool primaryKey: false,
      PropertyType databaseType,
      bool nullable: false,
      dynamic defaultValue,
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
  AttributeHint.fromAttributes(AttributeHint source, PropertyType databaseType)
      : this.databaseType = databaseType,
        this.isPrimaryKey = source.isPrimaryKey,
        this.isNullable = source.isNullable,
        this.defaultValue = source.defaultValue,
        this.isUnique = source.isUnique,
        this.isIndexed = source.isIndexed,
        this.shouldOmitByDefault = source.shouldOmitByDefault,
        this.autoincrement = source.autoincrement;
}

/// Metadata for a model type property that indicates it can be used in [readMap] and [asMap], but is not persisted.
const TransientAttribute transientAttribute = const TransientAttribute(availableAsInput: true, availableAsOutput: true);

/// Metadata for a model type property that indicates it can be used in [readMap], but is not persisted.
const TransientAttribute transientInputAttribute = const TransientAttribute(availableAsInput: true, availableAsOutput: false);

/// Metadata for a model type property that indicates it can be used in [asMap], but is not persisted.
const TransientAttribute transientOutputAttribute = const TransientAttribute(availableAsInput: false, availableAsOutput: true);

/// Metadata to associate with a property to indicate it is not a column, but is part of the Model object.
class TransientAttribute {
  final bool isAvailableAsInput;
  final bool isAvailableAsOutput;
  const TransientAttribute({bool availableAsInput: true, bool availableAsOutput: true}) :
        isAvailableAsInput = availableAsInput, isAvailableAsOutput = availableAsOutput;
}
