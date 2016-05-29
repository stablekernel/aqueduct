part of aqueduct;

class ModelEntity {

  /// Creates an instance of a ModelEntity.
  ///
  /// You should never call this method directly, it will be called by [DataModel] instances.
  ModelEntity(this.dataModel, this.instanceTypeMirror, this.persistentInstanceTypeMirror) {

  }

  /// The type of instances represented by this entity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. Applications
  /// use instance types. This value is the [ClassMirror] on that tpye.
  final ClassMirror instanceTypeMirror;

  /// The type of persistent instances represented by this enity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. This value
  /// is the [ClassMirror] on the persistent portion of a [Model] object.
  final ClassMirror persistentInstanceTypeMirror;

  /// The [DataModel] this instance belongs to.
  final DataModel dataModel;

  /// All attribute values of this entity.
  ///
  /// An attribute maps to a single column or field in a database that is a single value, such as a string, integer, etc.
  /// The keys are the case-sensitive name of the attribute. Values that represent a relationship to another object
  /// are not stored in [attributes].
  Map<String, AttributeDescription> attributes;

  /// All relationship values of this entity.
  ///
  /// A relationship represents a value that is another [Model] or [List] of [Model]s. Not all relationships
  /// correspond to a column or field in a database. In a relational database, if the [RelationshipDescription]
  /// has a [relationshipType] of [RelationshipType.belongsTo], the relationship represents the foreign key column.
  /// Keys are the case-sensitive name of the relationship.
  Map<String, RelationshipDescription> relationships;

  /// All properties (relationships and attributes) of this entity.
  ///
  /// The string key is the name of the property, case-sensitive. Values will be instances of either [AttributeDescription]
  /// or [RelationshipDescription]. This is the concatenation of [attributes] and [relationships].
  Map<String, PropertyDescription> get properties {
    var all = new Map.from(attributes);
    if (relationships != null) {
      all.addAll(relationships);
    }
    return all;
  }

  /// The list of default properties returned when querying an instance of this type.
  ///
  /// By default, a [Query] will return all the properties named in this list. You may specify
  /// a different set of properties by setting the [Query]'s [resultKeys] value. The default
  /// set of properties is a list of all attributes that do not have the [omitByDefault] flag
  /// set in their [Attributes] and all [RelationshipType.belongsTo] relationships.
  List<String> get defaultProperties {
    if (_defaultProperties == null) {
      _defaultProperties = attributes.values
          .where((prop) => prop.isIncludedInDefaultResultSet)
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

  /// Name of primaryKey property.
  ///
  /// If this has a primary key (as determined by the having an [Attributes] with [Attributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null.
  String get primaryKey {
    return _primaryKey;
  }
  String _primaryKey;

  /// Name of table in database.
  ///
  /// By default, the table will be named by the backing type, e.g., a model class defined as class User extends Model<_User> implements _User has a backing
  /// type of _User. The table will be named _User. You may implement the static method tableName that returns a [String] to change this table name
  /// to that methods returned value.
  String get tableName {
    return _tableName;
  }
  String _tableName;

  /// Derived from this' [tableName].
  int get hashCode {
    return tableName.hashCode;
  }

  Model instanceFromMappingElements(List<MappingElement> elements) {
    Model instance = instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;

    elements.forEach((e) {
      if (e is! JoinElement) {
        if (e.property is RelationshipDescription) {
          // A belongsTo relationship, keep the foreign key.
          if (e.value != null) {
            RelationshipDescription relDesc = e.property;
            Model innerInstance = relDesc.destinationEntity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
            innerInstance.dynamicBacking[relDesc.destinationEntity.primaryKey] = e.value;
            instance.dynamicBacking[e.property.name] = innerInstance;
          }
        } else {
          instance.dynamicBacking[e.property.name] = e.value;
        }
      }
    });

    return instance;
  }


  /// Two entities are considered equal if they have the same [tableName].
  operator ==(ModelEntity other) {
    return tableName == other.tableName;
  }

  String toString() {
    return "ModelEntity on $tableName";
  }
}