part of monadart;


/// Possible values for a delete rule in a [RelationshipAttribute]
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

/// An annotation for a Model property to indicate the values are instances of one or more Models.
///
/// To be used as metadata on a property declaration in model entity class.
class RelationshipAttribute {
  /// The type of relationship.
  ///
  /// If the type is [hasOne] or [hasMany], the inverse relationship must be [belongsTo]. Likewise, a [belongsTo] relationship must have a [hasOne] or [hasMany]
  /// inverse relationship.
  final RelationshipType type;

  /// The delete rule for this relationship.
  ///
  /// See [RelationshipDeleteRule] for possible values.
  final RelationshipDeleteRule deleteRule;

  /// The name of the property on the related object that this relationship ensures referential integrity through.
  ///
  /// By default, this will be the primary key of the related object.
  final String referenceKey;

  /// The required name of the inverse property in the related model.
  ///
  /// For example, a social network 'Post' model object
  /// would have a 'creator' property, related to the user that created it. Likewise, the User would have a 'posts' property
  /// of posts it has created. The inverseName of 'posts' on the User would be 'creator' and the inverseName of 'creator'
  /// on the Post would be 'posts'. All relationships must have an inverse.
  final String inverseKey;

  /// Constructor for relationship to be used as metadata for a model property.
  ///
  /// [type] and [inverseName] are required. All Relationships must have an inverse in the corresponding model.
  const RelationshipAttribute(RelationshipType type, String inverseKey,
      {RelationshipDeleteRule deleteRule: RelationshipDeleteRule.nullify,
      String referenceKey: null})
      : this.type = type,
        this.inverseKey = inverseKey,
        this.deleteRule = deleteRule,
        this.referenceKey = referenceKey;

  const RelationshipAttribute.hasMany(String inverseKey) :
        this.type = RelationshipType.hasMany,
        this.inverseKey = inverseKey,
        this.deleteRule = RelationshipDeleteRule.nullify,
        this.referenceKey = null;

  const RelationshipAttribute.hasOne(String inverseKey) :
        this.type = RelationshipType.hasOne,
        this.inverseKey = inverseKey,
        this.deleteRule = RelationshipDeleteRule.nullify,
        this.referenceKey = null;

  const RelationshipAttribute.belongsTo(String inverseKey, {RelationshipDeleteRule deleteRule: RelationshipDeleteRule.nullify, String referenceKey: null}) :
        this.type = RelationshipType.belongsTo,
        this.inverseKey = inverseKey,
        this.deleteRule = deleteRule,
        this.referenceKey = referenceKey;
}


/// A declaration annotation for the options on a property in a entity class.
///
/// By default, simply declaring a a property in a entity class will make it a database field
/// and its persistence information will be derived from its type.
/// If, however, the property needs any of the attributes defined by this class, it should be annotated.
class Attributes {
  /// When true, indicates that this model property is the primary key.
  ///
  /// Only one property of a class may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the inquirer adapter will use the appropriate type for Dart type, e.g. a Dart String is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final String databaseType;

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
  /// This flag will remove the associated property from the result set unless it is explicitly specified by [resultKeys].
  final bool shouldOmitByDefault;

  /// The metadata constructor.
  const Attributes(
      {bool primaryKey: false,
      String databaseType,
      bool nullable: false,
      dynamic defaultValue,
      bool unique: false,
      bool indexed: false,
      bool omitByDefault: false})
      : this.isPrimaryKey = primaryKey,
        this.databaseType = databaseType,
        this.isNullable = nullable,
        this.defaultValue = defaultValue,
        this.isUnique = unique,
        this.isIndexed = indexed,
        this.shouldOmitByDefault = omitByDefault;

  /// A supporting constructor to support modifying Attributes.
  Attributes.fromAttributes(Attributes source, String databaseType)
      : this.databaseType = databaseType,
        this.isPrimaryKey = source.isPrimaryKey,
        this.isNullable = source.isNullable,
        this.defaultValue = source.defaultValue,
        this.isUnique = source.isUnique,
        this.isIndexed = source.isIndexed,
        this.shouldOmitByDefault = source.shouldOmitByDefault;
}

const Mappable mappable = const Mappable(availableAsInput: true, availableAsOutput: true);
const Mappable mappableInput = const Mappable(availableAsInput: true, availableAsOutput: false);
const Mappable mappableOutput = const Mappable(availableAsInput: false, availableAsOutput: true);

/// Metadata to associate with a property to indicate it is not a column, but is part of the Model object.
///
///
class Mappable {
  final bool isAvailableAsInput;
  final bool isAvailableAsOutput;
  const Mappable({bool availableAsInput: true, bool availableAsOutput: true}) :
        isAvailableAsInput = availableAsInput, isAvailableAsOutput = availableAsOutput;
}
