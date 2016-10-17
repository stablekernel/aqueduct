part of aqueduct;

/// Mapping information between a table in a database and a [Model] object.
///
/// An entity defines the mapping between a database table and [Model] subclass. It is a necessary component of the overall ORM capabilities
/// of Aqueduct. It may also be used at runtime to reflect on the database table and [Model] that represents that table in a more meaningful way.
///
/// Instances of this class are automatically created by [DataModel]. In general, you do not need to use instances
/// of this class.
///
/// An entity describes the properties that a subclass of [Model] will have and their representation in the underlying database.
/// Each of these properties are represented by an instance of a [PropertyDescription] subclass. A property is either an attribute or a relationship.
///
/// Attribute values are scalar (see [PropertyType]) - [int], [String], [DateTime], [double] and [bool].
/// Attributes are typically backed by a column in the underlying database for a [Model], but may also represent transient values
/// defined by the [instanceType].
/// Attributes are represented by [AttributeDescription].
///
/// The value of a relationship property is a reference to another [Model]. If a relationship property has [RelationshipInverse] metadata,
/// the property is backed be a foreign key column in the underlying database. Relationships are represented by [RelationshipDescription].
class ModelEntity {
  /// Creates an instance of a ModelEntity.
  ///
  /// You should never call this method directly, it will be called by [DataModel].
  ModelEntity(this.dataModel, this.instanceType, this.persistentType);

  /// The type of instances represented by this entity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. Applications
  /// use instances of the instance type to work with queries and data from the database table this entity represents. This value is the [ClassMirror] on that type.
  final ClassMirror instanceType;

  /// The type of persistent instances represented by this entity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. The system uses this type to define
  /// the mapping to the underlying database table. This value is the [ClassMirror] on the persistent portion of a [Model] object.
  final ClassMirror persistentType;

  /// The [DataModel] this instance belongs to.
  final DataModel dataModel;

  /// Schema of the model as returned in a response to use in generating documentation.
  APISchemaObject get documentedResponseSchema {
    return new APISchemaObject()
      ..title = MirrorSystem.getName(instanceType.simpleName)
      ..type = APISchemaObject.TypeObject
      ..properties = _propertiesForEntity(this);
  }

  /// Schema of the model as returned from a request to use in generating documentation.
  APISchemaObject get documentedRequestSchema {
    return new APISchemaObject()
      ..title = MirrorSystem.getName(instanceType.simpleName)
      ..type = APISchemaObject.TypeObject
      ..properties = _propertiesForEntity(this, asRequestObject: true);
  }

  /// All attribute values of this entity.
  ///
  /// An attribute maps to a single column or field in a database that is a scalar value, such as a string, integer, etc. or a
  /// transient property declared in the instance type.
  /// The keys are the case-sensitive name of the attribute. Values that represent a relationship to another object
  /// are not stored in [attributes].
  Map<String, AttributeDescription> attributes;

  /// All relationship values of this entity.
  ///
  /// A relationship represents a value that is another [Model] or [OrderedSet] of [Model]s. Not all relationships
  /// correspond to a column or field in a database, only those with [RelationshipInverse] metadata (see also [RelationshipType.belongsTo]). In
  /// this case, the underlying database column is a foreign key reference. The underlying database does not have storage
  /// for [RelationshipType.hasMany] or [RelationshipType.hasOne] properties, as those values are derived by the foreign key reference
  /// on the inverse relationship property.
  /// Keys are the case-sensitive name of the relationship.
  Map<String, RelationshipDescription> relationships;

  /// All properties (relationships and attributes) of this entity.
  ///
  /// The string key is the name of the property, case-sensitive. Values will be instances of either [AttributeDescription]
  /// or [RelationshipDescription]. This is the concatenation of [attributes] and [relationships].
  Map<String, PropertyDescription> get properties {
    var all = new Map.from(attributes) as Map<String, PropertyDescription>;
    if (relationships != null) {
      all.addAll(relationships);
    }
    return all;
  }

  /// The list of default properties returned when querying an instance of this type.
  ///
  /// By default, a [Query] will return all the properties named in this list. You may specify
  /// a different set of properties by setting the [Query]'s [resultProperties] value. The default
  /// set of properties is a list of all attributes that do not have the [omitByDefault] flag
  /// set in their [ColumnAttributes] and all [RelationshipType.belongsTo] relationships.
  List<String> get defaultProperties {
    if (_defaultProperties == null) {
      _defaultProperties = attributes.values
          .where((prop) => prop.isIncludedInDefaultResultSet)
          .where((prop) => !prop.isTransient)
          .map((prop) => prop.name)
          .toList();

      _defaultProperties.addAll(relationships.values
          .where((prop) => prop.isIncludedInDefaultResultSet && prop.relationshipType == RelationshipType.belongsTo)
          .map((prop) => prop.name)
          .toList());
    }
    return _defaultProperties;
  }
  List<String> _defaultProperties;

  /// Name of primary key property.
  ///
  /// If this has a primary key (as determined by the having an [ColumnAttributes] with [ColumnAttributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null. Entities should always have a primary key.
  String get primaryKey {
    return _primaryKey;
  }
  String _primaryKey;

  /// Name of table in database this entity maps to.
  ///
  /// By default, the table will be named by the persistent type, e.g., a model declared as so will have a [tableName] of '_User'.
  ///
  ///       class User extends Model<_User> implements _User {}
  ///       class _User { ... }
  ///
  /// You may implement the static method [tableName] on the persistent type to return a [String] table
  /// name override this default.
  String get tableName {
    return _tableName;
  }
  String _tableName;

  /// Derived from this' [tableName].
  int get hashCode {
    return tableName.hashCode;
  }

  /// Creates a new instance of this entity's instance type.
  Model newInstance() {
    var model = instanceType.newInstance(new Symbol(""), []).reflectee as Model;
    model.entity = this;
    return model;
  }

  /// Creates an instance of this entity from a list of [MappingElement]s.
  ///
  /// This method is used by a [ModelContext] to instantiate entities from a row
  /// returned from a database. It will initialize all column values, including belongsTo
  /// relationships. It will not populate data from hasMany or hasOne relationships
  /// that were populated in a join query, as this is the responsibility of the context.
  Model instanceFromMappingElements(List<MappingElement> elements) {
    Model instance = newInstance();

    elements.forEach((e) {
      if (e is! JoinMappingElement) {
        if (e.property is RelationshipDescription) {
          // A belongsTo relationship, keep the foreign key.
          if (e.value != null) {
            RelationshipDescription relDesc = e.property;
            Model innerInstance = relDesc.destinationEntity.newInstance();
            innerInstance[relDesc.destinationEntity.primaryKey] = e.value;
            instance[e.property.name] = innerInstance;
          }
        } else {
          instance[e.property.name] = e.value;
        }
      }
    });

    return instance;
  }

  Map<String, APISchemaObject> _propertiesForEntity(ModelEntity me, {bool shallow: false, bool asRequestObject: false}) {
    Map<String, APISchemaObject> schemaProperties = {};

    if (shallow) {
      // Only include the primary key
      var primaryKeyAttribute = me.attributes[me.primaryKey];
      schemaProperties[me.primaryKey] = new APISchemaObject()
        ..title = primaryKeyAttribute.name
        ..type = _schemaObjectTypeForPropertyType(primaryKeyAttribute.type)
        ..format = _schemaObjectFormatForPropertyType(primaryKeyAttribute.type);

      return schemaProperties;
    }

    me.attributes.values
        .where((attribute) => attribute.isIncludedInDefaultResultSet || (attribute.transientStatus?.isAvailableAsOutput ?? false))
        .where((attribute) => !asRequestObject || (asRequestObject && !attribute.autoincrement))
        .forEach((attribute) {
          schemaProperties[attribute.name] = new APISchemaObject()
            ..title = attribute.name
            ..type = _schemaObjectTypeForPropertyType(attribute.type)
            ..format = _schemaObjectFormatForPropertyType(attribute.type);
        });

    me.relationships.values
        .where((relationship) => relationship.isIncludedInDefaultResultSet)
        .where((relationship) => relationship.relationshipType == RelationshipType.belongsTo)
        .forEach((relationship) {
          schemaProperties[relationship.name] = new APISchemaObject()
            ..title = relationship.name
            ..type = APISchemaObject.TypeObject
            ..properties = _propertiesForEntity(relationship.destinationEntity, shallow: true);
        });

    return schemaProperties;
  }

  String _schemaObjectTypeForPropertyType(PropertyType pt) {
    switch (pt) {
      case PropertyType.integer:
      case PropertyType.bigInteger:
        return APISchemaObject.TypeInteger;
      case PropertyType.string:
      case PropertyType.datetime:
        return APISchemaObject.TypeString;
      case PropertyType.boolean:
        return APISchemaObject.TypeBoolean;
      case PropertyType.doublePrecision:
        return APISchemaObject.TypeNumber;
      case PropertyType.transientList:
        return APISchemaObject.TypeArray;
      case PropertyType.transientMap:
        return APISchemaObject.TypeObject;
      default:
        return null;
    }
  }

  String _schemaObjectFormatForPropertyType(PropertyType pt) {
    switch (pt) {
      case PropertyType.integer:
        return APISchemaObject.FormatInt32;
      case PropertyType.bigInteger:
        return APISchemaObject.FormatInt64;
      case PropertyType.datetime:
        return APISchemaObject.FormatDateTime;
      case PropertyType.doublePrecision:
        return APISchemaObject.FormatDouble;
      default:
        return null;
    }
  }

  /// Two entities are considered equal if they have the same [tableName].
  operator ==(dynamic other) {
    return tableName == other.tableName;
  }

  String toString() {
    return "ModelEntity on $tableName";
  }
}