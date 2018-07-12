import 'dart:mirrors';
import 'package:aqueduct/src/db/managed/backing.dart';
import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';

import 'managed.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import '../query/query.dart';
import 'relationship_type.dart';

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
/// The value of a relationship property is a reference to another [ManagedObject]. If a relationship property has [Relate] metadata,
/// the property is backed be a foreign key column in the underlying database. Relationships are represented by [ManagedRelationshipDescription].
class ManagedEntity implements APIComponentDocumenter {
  /// Creates an instance of this type..
  ///
  /// You should never call this method directly, it will be called by [ManagedDataModel].
  ManagedEntity(this.dataModel, this._tableName, this.instanceType, this.tableDefinition);

  /// The name of this entity.
  ///
  /// This name will match the name of [instanceType].
  String get name => MirrorSystem.getName(instanceType.simpleName);

  /// The type of instances represented by this entity.
  ///
  /// Managed objects are made up of two components, a table definition and an instance type. Applications
  /// use instances of the instance type to work with queries and data from the database table this entity represents. This value is the [ClassMirror] on that type.
  final ClassMirror instanceType;

  /// The type of persistent instances represented by this entity.
  ///
  /// Managed objects are made up of two components, a table definition and an instance type. The system uses this type to define
  /// the mapping to the underlying database table. This value is the [ClassMirror] on the persistent portion of a [ManagedObject] object.
  final ClassMirror tableDefinition;

  /// The [ManagedDataModel] this instance belongs to.
  final ManagedDataModel dataModel;

  /// All attribute values of this entity.
  ///
  /// An attribute maps to a single column or field in a database that is a scalar value, such as a string, integer, etc. or a
  /// transient property declared in the instance type.
  /// The keys are the case-sensitive name of the attribute. Values that represent a relationship to another object
  /// are not stored in [attributes].
  Map<String, ManagedAttributeDescription> get attributes => _attributes;

  set attributes(Map<String, ManagedAttributeDescription> m) {
    _attributes = m;
    _primaryKey = m.values
        .firstWhere((attrDesc) => attrDesc.isPrimaryKey,
            orElse: () => throw new ManagedDataModelError.noPrimaryKey(this))
        ?.name;
  }

  /// All relationship values of this entity.
  ///
  /// A relationship represents a value that is another [ManagedObject] or [ManagedSet] of [ManagedObject]s. Not all relationships
  /// correspond to a column or field in a database, only those with [Relate] metadata (see also [ManagedRelationshipType.belongsTo]). In
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
    var all = new Map<String, ManagedPropertyDescription>.from(attributes);
    if (relationships != null) {
      all.addAll(relationships);
    }
    return all;
  }

  /// Set of properties that, together, are unique for each instance of this entity.
  ///
  /// If non-null, each instance of this entity is unique for the combination of values
  /// for these properties. Instances may have the same values for each property in [uniquePropertySet],
  /// but cannot have the same value for all properties in [uniquePropertySet]. This differs from setting
  /// a single property as unique with [Column], where each instance has
  /// a unique value for that property.
  ///
  /// This value is set by adding [Table] to the table definition of a [ManagedObject].
  List<ManagedPropertyDescription> uniquePropertySet;

  /// List of [ManagedValidator]s for attributes of this entity.
  ///
  /// All validators for all [attributes] in one, flat list. Order is undefined.
  List<ManagedValidator> validators;

  /// The list of default properties returned when querying an instance of this type.
  ///
  /// By default, a [Query] will return all the properties named in this list. You may specify
  /// a different set of properties by setting the [Query.returningProperties] value. The default
  /// set of properties is a list of all attributes that do not have the [Column.shouldOmitByDefault] flag
  /// set in their [Column] and all [ManagedRelationshipType.belongsTo] relationships.
  List<String> get defaultProperties {
    if (_defaultProperties == null) {
      _defaultProperties = attributes.values
          .where((prop) => prop.isIncludedInDefaultResultSet)
          .where((prop) => !prop.isTransient)
          .map((prop) => prop.name)
          .toList();

      _defaultProperties.addAll(relationships.values
          .where(
              (prop) => prop.isIncludedInDefaultResultSet && prop.relationshipType == ManagedRelationshipType.belongsTo)
          .map((prop) => prop.name)
          .toList());
    }
    return _defaultProperties;
  }

  /// Name of primary key property.
  ///
  /// If this has a primary key (as determined by the having an [Column] with [Column.isPrimaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null. Entities should always have a primary key.
  String get primaryKey {
    return _primaryKey;
  }

  ManagedAttributeDescription get primaryKeyAttribute {
    return attributes[primaryKey];
  }

  /// A map from accessor symbol name to property name.
  ///
  /// This map should not be modified.
  Map<Symbol, String> symbolMap;

  /// Name of table in database this entity maps to.
  ///
  /// By default, the table will be named by the table definition, e.g., a managed object declared as so will have a [tableName] of '_User'.
  ///
  ///       class User extends ManagedObject<_User> implements _User {}
  ///       class _User { ... }
  ///
  /// You may implement the static method [tableName] on the table definition of a [ManagedObject] to return a [String] table
  /// name override this default.
  String get tableName {
    return _tableName;
  }

  String _tableName;
  String _primaryKey;
  List<String> _defaultProperties;
  Map<String, ManagedAttributeDescription> _attributes;

  /// Derived from this' [tableName].
  @override
  int get hashCode {
    return tableName.hashCode;
  }

  /// Creates a new instance of this entity's instance type.
  ///
  /// By default, the returned object will use a normal value backing map.
  /// If [backing] is non-null, it will be the backing map of the returned object.
  T instanceOf<T extends ManagedObject>({ManagedBacking backing}) {
    if (backing != null) {
      return ManagedObject.instantiateDynamic(this, backing: backing) as T;
    }

    return ManagedObject.instantiateDynamic(this) as T;
  }

  /// Returns an attribute in this entity for a property selector.
  ///
  /// Invokes [identifyProperties] with [propertyIdentifier], and ensures that a single attribute
  /// on this entity was selected. Returns that attribute.
  ManagedAttributeDescription identifyAttribute<T, U extends ManagedObject>(T propertyIdentifier(U x)) {
    final keyPaths = identifyProperties(propertyIdentifier);
    if (keyPaths.length != 1) {
      throw new ArgumentError("Invalid property selector. Cannot access more than one property for this operation.");
    }

    final firstKeyPath = keyPaths.first;
    if (firstKeyPath.dynamicElements != null) {
      throw new ArgumentError("Invalid property selector. Cannot access subdocuments for this operation.");
    }

    final elements = firstKeyPath.path;
    if (elements.length > 1) {
      throw new ArgumentError("Invalid property selector. Cannot use relationships for this operation.");
    }

    final propertyName = elements.first.name;
    var attribute = attributes[propertyName];
    if (attribute == null) {
      if (relationships.containsKey(propertyName)) {
        throw new ArgumentError(
            "Invalid property selection. Property '$propertyName' on "
                "'${name}' "
                "is a relationship and cannot be selected for this operation.");
      } else {
        throw new ArgumentError(
            "Invalid property selection. Column '$propertyName' does not "
                "exist on table '${tableName}'.");
      }
    }

    return attribute;
  }

  /// Returns a relationship in this entity for a property selector.
  ///
  /// Invokes [identifyProperties] with [propertyIdentifier], and ensures that a single relationship
  /// on this entity was selected. Returns that relationship.
  ManagedRelationshipDescription identifyRelationship<T, U extends ManagedObject>(T propertyIdentifier(U x)) {
    final keyPaths = identifyProperties(propertyIdentifier);
    if (keyPaths.length != 1) {
      throw new ArgumentError("Invalid property selector. Cannot access more than one property for this operation.");
    }

    final firstKeyPath = keyPaths.first;
    if (firstKeyPath.dynamicElements != null) {
      throw new ArgumentError("Invalid property selector. Cannot access subdocuments for this operation.");
    }

    final elements = firstKeyPath.path;
    if (elements.length > 1) {
      throw new ArgumentError("Invalid property selector. Cannot identify a nested relationship for this operation.");
    }

    final propertyName = elements.first.name;
    var desc = relationships[propertyName];
    if (desc == null) {
      throw new ArgumentError("Invalid property selection. Relationship named '$propertyName' on table '${tableName}' is not a relationship.");
    }

    return desc;
  }

  /// Returns a property selected by [propertyIdentifier].
  ///
  /// Invokes [identifyProperties] with [propertyIdentifier], and ensures that a single property
  /// on this entity was selected. Returns that property.
  KeyPath identifyProperty<T, U extends ManagedObject>(T propertyIdentifier(U x)) {
    final properties = identifyProperties(propertyIdentifier);
    if (properties.length != 1) {
      throw new ArgumentError("Invalid property selector. Must reference a single property only.");
    }

    return properties.first;
  }

  /// Returns a list of properties selected by [propertiesIdentifier].
  ///
  /// Each selected property in [propertiesIdentifier] is returned in a [KeyPath] object that fully identifies the
  /// property relative to this entity.
  List<KeyPath> identifyProperties<T, U extends ManagedObject>(T propertiesIdentifier(U x)) {
    final tracker = new ManagedAccessTrackingBacking();
    var obj = instanceOf<U>(backing: tracker);
    propertiesIdentifier(obj);

    return tracker.keyPaths;
  }

  /// Two entities are considered equal if they have the same [tableName].
  @override
  bool operator ==(dynamic other) {
    return tableName == other.tableName;
  }

  @override
  String toString() {
    return "ManagedEntity on $tableName";
  }

  @override
  void documentComponents(APIDocumentContext context) {
    final schemaProperties = <String, APISchemaObject>{};
    final obj = new APISchemaObject.object(schemaProperties)
      ..title = "${name}";

    // Documentation comments
    context.defer(() async {
      final entityDocs = await DocumentedElement.get(instanceType.reflectedType);
      obj.description = entityDocs.description ?? "";
      if (!(entityDocs.summary.isEmpty)) {
        obj.title = entityDocs.summary;
      }

      if (uniquePropertySet != null) {
        final propString = uniquePropertySet.map((s) => "'${s.name}'").join(", ");
        obj.description += "\nNo two objects may have the same value for all of: $propString.";
      }
    });

    properties.forEach((name, def) {
      if (def is ManagedAttributeDescription && !def.isIncludedInDefaultResultSet && !def.isTransient) {
        return;
      }

      final schemaProperty = def.documentSchemaObject(context);
      schemaProperties[name] = schemaProperty;

      context.defer(() async {
        DocumentedElement attrDocs;
        if (def is ManagedAttributeDescription && def.isTransient) {
          final entityDocs = await DocumentedElement.get(instanceType.reflectedType);
          attrDocs = entityDocs[new Symbol(name)];
        } else {
          final entityDocs = await DocumentedElement.get(tableDefinition.reflectedType);
          attrDocs = entityDocs[new Symbol(name)];
        }

        schemaProperty.title = attrDocs?.summary;
        schemaProperty.description = (attrDocs?.description ?? "") + (schemaProperty.description ?? "");
      });
    });

    context.schema
        .register(name, obj, representation: instanceType.reflectedType);
  }
}
