import 'dart:mirrors';
import 'managed.dart';
import '../../http/documentable.dart';
import '../query/query.dart';

/// Mapping information between a table in a database and a [ManagedObject] object.
///
/// An entity defines the mapping between a database table and [ManagedObject] subclass. Entities
/// are created by declaring [ManagedObject] subclasses and instantiating a [ManagedDataModel].
/// In general, you do not need to use or create instances of this class.
///
/// An entity describes the properties that a subclass of [ManagedObject] will have and their representation in the underlying database.
/// Each of these properties are represented by an instance of a [ManagedPropertyDescription] subclass. A property is either an attribute or a relationship.
///
/// Attribute values are scalar (see [ManagedPropertyType]) - [int], [String], [DateTime], [double] and [bool].
/// Attributes are typically backed by a column in the underlying database for a [ManagedObject], but may also represent transient values
/// defined by the [instanceType].
/// Attributes are represented by [ManagedAttributeDescription].
///
/// The value of a relationship property is a reference to another [ManagedObject]. If a relationship property has [ManagedRelationship] metadata,
/// the property is backed be a foreign key column in the underlying database. Relationships are represented by [ManagedRelationshipDescription].
class ManagedEntity {
  /// Creates an instance of this type..
  ///
  /// You should never call this method directly, it will be called by [ManagedDataModel].
  ManagedEntity(
      this.dataModel, this._tableName, this.instanceType, this.persistentType);

  /// The type of instances represented by this entity.
  ///
  /// Managed objects are made up of two components, a persistent type and an instance type. Applications
  /// use instances of the instance type to work with queries and data from the database table this entity represents. This value is the [ClassMirror] on that type.
  final ClassMirror instanceType;

  /// The type of persistent instances represented by this entity.
  ///
  /// Managed objects are made up of two components, a persistent type and an instance type. The system uses this type to define
  /// the mapping to the underlying database table. This value is the [ClassMirror] on the persistent portion of a [ManagedObject] object.
  final ClassMirror persistentType;

  /// The [ManagedDataModel] this instance belongs to.
  final ManagedDataModel dataModel;

  /// Schema of the managed object as returned in a response to use in generating documentation.
  APISchemaObject get documentedResponseSchema {
    return new APISchemaObject()
      ..title = MirrorSystem.getName(instanceType.simpleName)
      ..type = APISchemaObject.TypeObject
      ..properties = _propertiesForEntity(this);
  }

  /// Schema of the managed object as returned from a request to use in generating documentation.
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

  Map<String, ManagedAttributeDescription> _attributes;
  Map<String, ManagedAttributeDescription> get attributes => _attributes;
  void set attributes(Map<String, ManagedAttributeDescription> m) {
    _attributes = m;
    _primaryKey = m.values
        .firstWhere((attrDesc) => attrDesc.isPrimaryKey, orElse: () => null)
        ?.name;
  }

  /// All relationship values of this entity.
  ///
  /// A relationship represents a value that is another [ManagedObject] or [ManagedSet] of [ManagedObject]s. Not all relationships
  /// correspond to a column or field in a database, only those with [ManagedRelationship] metadata (see also [ManagedRelationshipType.belongsTo]). In
  /// this case, the underlying database column is a foreign key reference. The underlying database does not have storage
  /// for [ManagedRelationshipType.hasMany] or [ManagedRelationshipType.hasOne] properties, as those values are derived by the foreign key reference
  /// on the inverse relationship property.
  /// Keys are the case-sensitive name of the relationship.
  Map<String, ManagedRelationshipDescription> relationships;

  /// All properties (relationships and attributes) of this entity.
  ///
  /// The string key is the name of the property, case-sensitive. Values will be instances of either [ManagedAttributeDescription]
  /// or [ManagedRelationshipDescription]. This is the concatenation of [attributes] and [relationships].
  Map<String, ManagedPropertyDescription> get properties {
    var all =
        new Map.from(attributes) as Map<String, ManagedPropertyDescription>;
    if (relationships != null) {
      all.addAll(relationships);
    }
    return all;
  }

  /// The list of default properties returned when querying an instance of this type.
  ///
  /// By default, a [Query] will return all the properties named in this list. You may specify
  /// a different set of properties by setting the [Query.returningProperties] value. The default
  /// set of properties is a list of all attributes that do not have the [omitByDefault] flag
  /// set in their [ManagedColumnAttributes] and all [ManagedRelationshipType.belongsTo] relationships.
  List<String> get defaultProperties {
    if (_defaultProperties == null) {
      _defaultProperties = attributes.values
          .where((prop) => prop.isIncludedInDefaultResultSet)
          .where((prop) => !prop.isTransient)
          .map((prop) => prop.name)
          .toList();

      _defaultProperties.addAll(relationships.values
          .where((prop) =>
              prop.isIncludedInDefaultResultSet &&
              prop.relationshipType == ManagedRelationshipType.belongsTo)
          .map((prop) => prop.name)
          .toList());
    }
    return _defaultProperties;
  }

  List<String> _defaultProperties;

  /// Name of primary key property.
  ///
  /// If this has a primary key (as determined by the having an [ManagedColumnAttributes] with [ManagedColumnAttributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null. Entities should always have a primary key.
  String get primaryKey {
    return _primaryKey;
  }

  String _primaryKey;

  ManagedAttributeDescription get primaryKeyAttribute {
    return properties[primaryKey];
  }

  /// Name of table in database this entity maps to.
  ///
  /// By default, the table will be named by the persistent type, e.g., a managed object declared as so will have a [tableName] of '_User'.
  ///
  ///       class User extends ManagedObject<_User> implements _User {}
  ///       class _User { ... }
  ///
  /// You may implement the static method [tableName] on the persistent type of a [ManagedObject] to return a [String] table
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
  ManagedObject newInstance() {
    var model =
        instanceType.newInstance(new Symbol(""), []).reflectee as ManagedObject;
    model.entity = this;
    return model;
  }

  Map<String, APISchemaObject> _propertiesForEntity(ManagedEntity me,
      {bool shallow: false, bool asRequestObject: false}) {
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
        .where((attribute) =>
            attribute.isIncludedInDefaultResultSet ||
            (attribute.transientStatus?.isAvailableAsOutput ?? false))
        .where((attribute) =>
            !asRequestObject || (asRequestObject && !attribute.autoincrement))
        .forEach((attribute) {
      schemaProperties[attribute.name] = new APISchemaObject()
        ..title = attribute.name
        ..type = _schemaObjectTypeForPropertyType(attribute.type)
        ..format = _schemaObjectFormatForPropertyType(attribute.type);
    });

    me.relationships.values
        .where((relationship) => relationship.isIncludedInDefaultResultSet)
        .where((relationship) =>
            relationship.relationshipType == ManagedRelationshipType.belongsTo)
        .forEach((relationship) {
      schemaProperties[relationship.name] = new APISchemaObject()
        ..title = relationship.name
        ..type = APISchemaObject.TypeObject
        ..properties =
            _propertiesForEntity(relationship.destinationEntity, shallow: true);
    });

    return schemaProperties;
  }

  String _schemaObjectTypeForPropertyType(ManagedPropertyType pt) {
    switch (pt) {
      case ManagedPropertyType.integer:
      case ManagedPropertyType.bigInteger:
        return APISchemaObject.TypeInteger;
      case ManagedPropertyType.string:
      case ManagedPropertyType.datetime:
        return APISchemaObject.TypeString;
      case ManagedPropertyType.boolean:
        return APISchemaObject.TypeBoolean;
      case ManagedPropertyType.doublePrecision:
        return APISchemaObject.TypeNumber;
      case ManagedPropertyType.transientList:
        return APISchemaObject.TypeArray;
      case ManagedPropertyType.transientMap:
        return APISchemaObject.TypeObject;
      default:
        return null;
    }
  }

  String _schemaObjectFormatForPropertyType(ManagedPropertyType pt) {
    switch (pt) {
      case ManagedPropertyType.integer:
        return APISchemaObject.FormatInt32;
      case ManagedPropertyType.bigInteger:
        return APISchemaObject.FormatInt64;
      case ManagedPropertyType.datetime:
        return APISchemaObject.FormatDateTime;
      case ManagedPropertyType.doublePrecision:
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
    return "ManagedEntity on $tableName";
  }
}
