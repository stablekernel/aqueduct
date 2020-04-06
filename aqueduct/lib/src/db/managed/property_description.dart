import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:open_api/v3.dart';
import 'package:runtime/runtime.dart';

import '../persistent_store/persistent_store.dart';
import '../query/query.dart';
import 'exception.dart';
import 'managed.dart';
import 'relationship_type.dart';
import 'type.dart';

/// Contains database column information and metadata for a property of a [ManagedObject] object.
///
/// Each property a [ManagedObject] object manages is described by an instance of [ManagedPropertyDescription], which contains useful information
/// about the property such as its name and type. Those properties are represented by concrete subclasses of this class, [ManagedRelationshipDescription]
/// and [ManagedAttributeDescription].
abstract class ManagedPropertyDescription {
  ManagedPropertyDescription(
      this.entity, this.name, this.type, this.declaredType,
      {bool unique = false,
      bool indexed = false,
      bool nullable = false,
      bool includedInDefaultResultSet = true,
      bool autoincrement = false,
      List<ManagedValidator> validators = const []})
      : isUnique = unique,
        isIndexed = indexed,
        isNullable = nullable,
        isIncludedInDefaultResultSet = includedInDefaultResultSet,
        autoincrement = autoincrement,
        _validators = validators {
    _validators?.forEach((v) => v.property = this);
  }

  /// A reference to the [ManagedEntity] that contains this property.
  final ManagedEntity entity;

  /// The value type of this property.
  ///
  /// Will indicate the Dart type and database column type of this property.
  final ManagedType type;

  /// The identifying name of this property.
  final String name;

  /// Whether or not this property must be unique to across all instances represented by [entity].
  ///
  /// Defaults to false.
  final bool isUnique;

  /// Whether or not this property should be indexed by a [PersistentStore].
  ///
  /// Defaults to false.
  final bool isIndexed;

  /// Whether or not this property can be null.
  ///
  /// Defaults to false.
  final bool isNullable;

  /// Whether or not this property is returned in the default set of [Query.returningProperties].
  ///
  /// This defaults to true. If true, when executing a [Query] that does not explicitly specify [Query.returningProperties],
  /// this property will be returned. If false, you must explicitly specify this property in [Query.returningProperties] to retrieve it from persistent storage.
  final bool isIncludedInDefaultResultSet;

  /// Whether or not this property should use an auto-incrementing scheme.
  ///
  /// By default, false. When true, it signals to the [PersistentStore] that this property should automatically be assigned a value
  /// by the database.
  final bool autoincrement;

  /// Whether or not this attribute is private or not.
  ///
  /// Private variables are prefixed with `_` (underscores). This properties are not read
  /// or written to maps and cannot be accessed from outside the class.
  ///
  /// This flag is not included in schemas documents used by database migrations and other tools.
  bool get isPrivate {
    return name.startsWith("_");
  }

  /// [ManagedValidator]s for this instance.
  List<ManagedValidator> get validators => _validators;

  final List<ManagedValidator> _validators;

  /// Whether or not a the argument can be assigned to this property.
  bool isAssignableWith(dynamic dartValue) => type.isAssignableWith(dartValue);

  /// Converts a value from a more complex value into a primitive value according to this instance's definition.
  ///
  /// This method takes a Dart representation of a value and converts it to something that can
  /// be used elsewhere (e.g. an HTTP body or database query). How this value is computed
  /// depends on this instance's definition.
  dynamic convertToPrimitiveValue(dynamic value);

  /// Converts a value to a more complex value from a primitive value according to this instance's definition.
  ///
  /// This method takes a non-Dart representation of a value (e.g. an HTTP body or database query)
  /// and turns it into a Dart representation . How this value is computed
  /// depends on this instance's definition.
  dynamic convertFromPrimitiveValue(dynamic value);

  /// The type of the variable that this property represents.
  final Type declaredType;

  /// Returns an [APISchemaObject] that represents this property.
  ///
  /// Used during documentation.
  APISchemaObject documentSchemaObject(APIDocumentContext context);

  static APISchemaObject _typedSchemaObject(ManagedType type) {
    switch (type.kind) {
      case ManagedPropertyType.integer:
        return APISchemaObject.integer();
      case ManagedPropertyType.bigInteger:
        return APISchemaObject.integer();
      case ManagedPropertyType.doublePrecision:
        return APISchemaObject.number();
      case ManagedPropertyType.string:
        return APISchemaObject.string();
      case ManagedPropertyType.datetime:
        return APISchemaObject.string(format: "date-time");
      case ManagedPropertyType.boolean:
        return APISchemaObject.boolean();
      case ManagedPropertyType.list:
        return APISchemaObject.array(
            ofSchema: _typedSchemaObject(type.elements));
      case ManagedPropertyType.map:
        return APISchemaObject.map(ofSchema: _typedSchemaObject(type.elements));
      case ManagedPropertyType.document:
        return APISchemaObject.freeForm();
    }

    throw UnsupportedError("Unsupported type '$type' when documenting entity.");
  }
}

/// Stores the specifics of database columns in [ManagedObject]s as indicated by [Column].
///
/// This class is used internally to manage data models. For specifying these attributes,
/// see [Column].
///
/// Attributes are the scalar values of a [ManagedObject] (as opposed to relationship values,
/// which are [ManagedRelationshipDescription] instances).
///
/// Each scalar property [ManagedObject] object persists is described by an instance of [ManagedAttributeDescription]. This class
/// adds two properties to [ManagedPropertyDescription] that are only valid for non-relationship types, [isPrimaryKey] and [defaultValue].
class ManagedAttributeDescription extends ManagedPropertyDescription {
  ManagedAttributeDescription(
      ManagedEntity entity, String name, ManagedType type, Type declaredType,
      {Serialize transientStatus,
      bool primaryKey = false,
      String defaultValue,
      bool unique = false,
      bool indexed = false,
      bool nullable = false,
      bool includedInDefaultResultSet = true,
      bool autoincrement = false,
      List<ManagedValidator> validators = const []})
      : isPrimaryKey = primaryKey,
        defaultValue = defaultValue,
        transientStatus = transientStatus,
        super(entity, name, type, declaredType,
            unique: unique,
            indexed: indexed,
            nullable: nullable,
            includedInDefaultResultSet: includedInDefaultResultSet,
            autoincrement: autoincrement,
            validators: validators);

  ManagedAttributeDescription.transient(ManagedEntity entity, String name,
      ManagedType type, Type declaredType, this.transientStatus)
      : isPrimaryKey = false,
        defaultValue = null,
        super(entity, name, type, declaredType,
            unique: false,
            indexed: false,
            nullable: false,
            includedInDefaultResultSet: false,
            autoincrement: false,
            validators: []);

  // ignore: prefer_constructors_over_static_methods
  static ManagedAttributeDescription make<T>(
      ManagedEntity entity, String name, ManagedType type,
      {Serialize transientStatus,
      bool primaryKey = false,
      String defaultValue,
      bool unique = false,
      bool indexed = false,
      bool nullable = false,
      bool includedInDefaultResultSet = true,
      bool autoincrement = false,
      List<ManagedValidator> validators = const []}) {
    return ManagedAttributeDescription(entity, name, type, T,
        transientStatus: transientStatus,
        primaryKey: primaryKey,
        defaultValue: defaultValue,
        unique: unique,
        indexed: indexed,
        nullable: nullable,
        includedInDefaultResultSet: includedInDefaultResultSet,
        autoincrement: autoincrement,
        validators: validators);
  }

  /// Whether or not this attribute is the primary key for its [ManagedEntity].
  ///
  /// Defaults to false.
  final bool isPrimaryKey;

  /// The default value for this attribute.
  ///
  /// By default, null. This value is a String, so the underlying persistent store is responsible for parsing it. This allows for default values
  /// that aren't constant values, such as database function calls.
  final String defaultValue;

  /// Whether or not this attribute is backed directly by the database.
  ///
  /// If [transientStatus] is non-null, this value will be true. Otherwise, the attribute is backed by a database field/column.
  bool get isTransient => transientStatus != null;

  /// Contains lookup table for string value of an enumeration to the enumerated value.
  ///
  /// Value is null when this attribute does not represent an enumerated type.
  ///
  /// If `enum Options { option1, option2 }` then this map contains:
  ///
  ///         {
  ///           "option1": Options.option1,
  ///           "option2": Options.option2
  ///          }
  ///
  Map<String, dynamic> get enumerationValueMap => type.enumerationMap;

  /// The validity of a transient attribute as input, output or both.
  ///
  /// If this property is non-null, the attribute is transient (not backed by a database field/column).
  final Serialize transientStatus;

  /// Whether or not this attribute is represented by a Dart enum.
  bool get isEnumeratedValue => enumerationValueMap != null;

  @override
  APISchemaObject documentSchemaObject(APIDocumentContext context) {
    final prop = ManagedPropertyDescription._typedSchemaObject(type)
      ..title = name;
    final buf = StringBuffer();

    // Add'l schema info
    prop.isNullable = isNullable;
    validators
        .forEach((v) => v.definition.constrainSchemaObject(context, prop));

    if (isEnumeratedValue) {
      prop.enumerated = prop.enumerated.map(convertToPrimitiveValue).toList();
    }

    if (isTransient) {
      if (transientStatus.isAvailableAsInput &&
          !transientStatus.isAvailableAsOutput) {
        prop.isWriteOnly = true;
      } else if (!transientStatus.isAvailableAsInput &&
          transientStatus.isAvailableAsOutput) {
        prop.isReadOnly = true;
      }
    }

    if (isUnique) {
      buf.writeln("No two objects may have the same value for this field.");
    }

    if (isPrimaryKey) {
      buf.writeln("This is the primary identifier for this object.");
    }

    if (defaultValue != null) {
      prop.defaultValue = defaultValue;
    }

    if (buf.isNotEmpty) {
      prop.description = buf.toString();
    }

    return prop;
  }

  @override
  String toString() {
    final flagBuffer = StringBuffer();
    if (isPrimaryKey) {
      flagBuffer.write("primary_key ");
    }
    if (isTransient) {
      flagBuffer.write("transient ");
    }
    if (autoincrement) {
      flagBuffer.write("autoincrementing ");
    }
    if (isUnique) {
      flagBuffer.write("unique ");
    }
    if (defaultValue != null) {
      flagBuffer.write("defaults to $defaultValue ");
    }
    if (isIndexed) {
      flagBuffer.write("indexed ");
    }
    if (isNullable) {
      flagBuffer.write("nullable ");
    } else {
      flagBuffer.write("required ");
    }

    return "- $name | $type | Flags: ${flagBuffer.toString()}";
  }

  @override
  dynamic convertToPrimitiveValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (type.kind == ManagedPropertyType.datetime && value is DateTime) {
      return value.toIso8601String();
    } else if (isEnumeratedValue) {
      // todo: optimize?
      return value.toString().split(".").last;
    } else if (type.kind == ManagedPropertyType.document && value is Document) {
      return value.data;
    }

    return value;
  }

  @override
  dynamic convertFromPrimitiveValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (type.kind == ManagedPropertyType.datetime) {
      if (value is! String) {
        throw ValidationException(["invalid input value for '$name'"]);
      }
      return DateTime.parse(value as String);
    } else if (type.kind == ManagedPropertyType.doublePrecision) {
      if (value is! num) {
        throw ValidationException(["invalid input value for '$name'"]);
      }
      return value.toDouble();
    } else if (isEnumeratedValue) {
      if (!enumerationValueMap.containsKey(value)) {
        throw ValidationException(["invalid option for key '$name'"]);
      }
      return enumerationValueMap[value];
    } else if (type.kind == ManagedPropertyType.document) {
      return Document(value);
    } else if (type.kind == ManagedPropertyType.list ||
        type.kind == ManagedPropertyType.map) {
      try {
        return entity.runtime.dynamicConvertFromPrimitiveValue(this, value);
      } on TypeCoercionException {
        throw ValidationException(["invalid input value for '$name'"]);
      }
    }

    return value;
  }
}

/// Contains information for a relationship property of a [ManagedObject].
class ManagedRelationshipDescription extends ManagedPropertyDescription {
  ManagedRelationshipDescription(
      ManagedEntity entity,
      String name,
      ManagedType type,
      Type declaredType,
      this.destinationEntity,
      this.deleteRule,
      this.relationshipType,
      this.inverseKey,
      {bool unique = false,
      bool indexed = false,
      bool nullable = false,
      bool includedInDefaultResultSet = true,
      List<ManagedValidator> validators = const []})
      : super(entity, name, type, declaredType,
            unique: unique,
            indexed: indexed,
            nullable: nullable,
            includedInDefaultResultSet: includedInDefaultResultSet,
            validators: validators);

  // ignore: prefer_constructors_over_static_methods
  static ManagedRelationshipDescription make<T>(
      ManagedEntity entity,
      String name,
      ManagedType type,
      ManagedEntity destinationEntity,
      DeleteRule deleteRule,
      ManagedRelationshipType relationshipType,
      String inverseKey,
      {bool unique = false,
      bool indexed = false,
      bool nullable = false,
      bool includedInDefaultResultSet = true,
      List<ManagedValidator> validators = const []}) {
    return ManagedRelationshipDescription(entity, name, type, T,
        destinationEntity, deleteRule, relationshipType, inverseKey,
        unique: unique,
        indexed: indexed,
        nullable: nullable,
        includedInDefaultResultSet: includedInDefaultResultSet,
        validators: validators);
  }

  /// The entity that this relationship's instances are represented by.
  final ManagedEntity destinationEntity;

  /// The delete rule for this relationship.
  final DeleteRule deleteRule;

  /// The type of relationship.
  final ManagedRelationshipType relationshipType;

  /// The name of the [ManagedRelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  final String inverseKey;

  /// The [ManagedRelationshipDescription] on [destinationEntity] that represents the inverse of this relationship.
  ManagedRelationshipDescription get inverse =>
      destinationEntity.relationships[inverseKey];

  /// Whether or not this relationship is on the belonging side.
  bool get isBelongsTo => relationshipType == ManagedRelationshipType.belongsTo;

  /// Whether or not a the argument can be assigned to this property.
  @override
  bool isAssignableWith(dynamic dartValue) {
    if (relationshipType == ManagedRelationshipType.hasMany) {
      return destinationEntity.runtime.isValueListOf(dartValue);
    }
    return destinationEntity.runtime.isValueInstanceOf(dartValue);
  }

  @override
  dynamic convertToPrimitiveValue(dynamic value) {
    if (value is ManagedSet) {
      return value
          .map((ManagedObject innerValue) => innerValue.asMap())
          .toList();
    } else if (value is ManagedObject) {
      // If we're only fetching the foreign key, don't do a full asMap
      if (relationshipType == ManagedRelationshipType.belongsTo &&
          value.backing.contents.length == 1 &&
          value.backing.contents.containsKey(destinationEntity.primaryKey)) {
        return {
          destinationEntity.primaryKey: value[destinationEntity.primaryKey]
        };
      }

      return value.asMap();
    } else if (value == null) {
      return null;
    }

    throw StateError(
        "Invalid relationship assigment. Relationship '$entity.$name' is not a 'ManagedSet' or 'ManagedObject'.");
  }

  @override
  dynamic convertFromPrimitiveValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (relationshipType == ManagedRelationshipType.belongsTo ||
        relationshipType == ManagedRelationshipType.hasOne) {
      if (value is! Map<String, dynamic>) {
        throw ValidationException(["invalid input type for '$name'"]);
      }

      final instance = destinationEntity.instanceOf()
        ..readFromMap(value as Map<String, dynamic>);

      return instance;
    }

    /* else if (relationshipType == ManagedRelationshipType.hasMany) { */

    if (value is! List) {
      throw ValidationException(["invalid input type for '$name'"]);
    }

    final instantiator = (dynamic m) {
      if (m is! Map<String, dynamic>) {
        throw ValidationException(["invalid input type for '$name'"]);
      }
      final instance = destinationEntity.instanceOf()
        ..readFromMap(m as Map<String, dynamic>);
      return instance;
    };
    return destinationEntity.setOf((value as List).map(instantiator));
  }

  @override
  APISchemaObject documentSchemaObject(APIDocumentContext context) {
    final relatedType =
        context.schema.getObjectWithType(inverse.entity.instanceType);

    if (relationshipType == ManagedRelationshipType.hasMany) {
      return APISchemaObject.array(ofSchema: relatedType)
        ..isReadOnly = true
        ..isNullable = true;
    } else if (relationshipType == ManagedRelationshipType.hasOne) {
      return relatedType
        ..isReadOnly = true
        ..isNullable = true;
    }

    final destPk = destinationEntity.primaryKeyAttribute;
    return APISchemaObject.object({
      destPk.name: ManagedPropertyDescription._typedSchemaObject(destPk.type)
    })
      ..title = name;
  }

  @override
  String toString() {
    var relTypeString = "has-one";
    switch (relationshipType) {
      case ManagedRelationshipType.belongsTo:
        relTypeString = "belongs to";
        break;
      case ManagedRelationshipType.hasMany:
        relTypeString = "has-many";
        break;
      case ManagedRelationshipType.hasOne:
        relTypeString = "has-a";
        break;
    }
    return "- $name -> '${destinationEntity.name}' | Type: $relTypeString | Inverse: ${inverseKey}";
  }
}
