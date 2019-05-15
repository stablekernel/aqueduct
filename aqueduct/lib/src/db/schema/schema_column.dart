import '../managed/managed.dart';
import 'schema.dart';

/// A portable representation of a database column.
///
/// Instances of this type contain the database-only details of a [ManagedPropertyDescription].
class SchemaColumn {
  /// Creates an instance of this type from [name], [type] and other properties.
  SchemaColumn(this.name, ManagedPropertyType type,
      {this.isIndexed = false,
      this.isNullable = false,
      this.autoincrement = false,
      this.isUnique = false,
      this.defaultValue,
      this.isPrimaryKey = false}) {
    _type = typeStringForType(type);
  }

  /// A convenience constructor for properties that represent foreign key relationships.
  SchemaColumn.relationship(this.name, ManagedPropertyType type,
      {this.isNullable = true,
      this.isUnique = false,
      this.relatedTableName,
      this.relatedColumnName,
      DeleteRule rule = DeleteRule.nullify}) {
    isIndexed = true;
    _type = typeStringForType(type);
    _deleteRule = deleteRuleStringForDeleteRule(rule);
  }

  /// Creates an instance of this type to mirror [desc].
  SchemaColumn.fromProperty(ManagedPropertyDescription desc) {
    name = desc.name;

    if (desc is ManagedRelationshipDescription) {
      isPrimaryKey = false;
      relatedTableName = desc.destinationEntity.tableName;
      relatedColumnName = desc.destinationEntity.primaryKey;
      _deleteRule = deleteRuleStringForDeleteRule(desc.deleteRule);
    } else if (desc is ManagedAttributeDescription) {
      defaultValue = desc.defaultValue;
      isPrimaryKey = desc.isPrimaryKey;
    }

    _type = typeStringForType(desc.type.kind);
    isNullable = desc.isNullable;
    autoincrement = desc.autoincrement;
    isUnique = desc.isUnique;
    isIndexed = desc.isIndexed;
  }

  /// Creates a copy of [otherColumn].
  SchemaColumn.from(SchemaColumn otherColumn) {
    name = otherColumn.name;
    _type = otherColumn._type;
    isIndexed = otherColumn.isIndexed;
    isNullable = otherColumn.isNullable;
    autoincrement = otherColumn.autoincrement;
    isUnique = otherColumn.isUnique;
    defaultValue = otherColumn.defaultValue;
    isPrimaryKey = otherColumn.isPrimaryKey;
    relatedTableName = otherColumn.relatedTableName;
    relatedColumnName = otherColumn.relatedColumnName;
    _deleteRule = otherColumn._deleteRule;
  }

  /// Creates an instance of this type from [map].
  ///
  /// Where [map] is typically created by [asMap].
  SchemaColumn.fromMap(Map<String, dynamic> map) {
    name = map["name"] as String;
    _type = map["type"] as String;
    isIndexed = map["indexed"] as bool;
    isNullable = map["nullable"] as bool;
    autoincrement = map["autoincrement"] as bool;
    isUnique = map["unique"] as bool;
    defaultValue = map["defaultValue"] as String;
    isPrimaryKey = map["primaryKey"] as bool;
    relatedTableName = map["relatedTableName"] as String;
    relatedColumnName = map["relatedColumnName"] as String;
    _deleteRule = map["deleteRule"] as String;
  }

  /// Creates an empty instance of this type.
  SchemaColumn.empty();

  /// The name of this column.
  String name;

  /// The [SchemaTable] this column belongs to.
  ///
  /// May be null if not assigned to a table.
  SchemaTable table;

  /// The [String] representation of this column's type.
  String get typeString => _type;

  /// The type of this column in a [ManagedDataModel].
  ManagedPropertyType get type => typeFromTypeString(_type);

  set type(ManagedPropertyType t) {
    _type = typeStringForType(t);
  }

  /// Whether or not this column is indexed.
  bool isIndexed = false;

  /// Whether or not this column is nullable.
  bool isNullable = false;

  /// Whether or not this column is autoincremented.
  bool autoincrement = false;

  /// Whether or not this column is unique.
  bool isUnique = false;

  /// The default value for this column when inserted into a database.
  String defaultValue;

  /// Whether or not this column is the primary key of its [table].
  bool isPrimaryKey = false;

  /// The related table name if this column is a foreign key column.
  ///
  /// If this column has a foreign key constraint, this property is the name
  /// of the referenced table.
  ///
  /// Null if this column is not a foreign key reference.
  String relatedTableName;

  /// The related column if this column is a foreign key column.
  ///
  /// If this column has a foreign key constraint, this property is the name
  /// of the reference column in [relatedTableName].
  String relatedColumnName;

  /// The delete rule for this column if it is a foreign key column.
  ///
  /// Undefined if not a foreign key column.
  DeleteRule get deleteRule => deleteRuleForDeleteRuleString(_deleteRule);

  set deleteRule(DeleteRule t) {
    _deleteRule = deleteRuleStringForDeleteRule(t);
  }

  /// Whether or not this column is a foreign key column.
  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  String _type;
  String _deleteRule;

  /// The differences between two columns.
  SchemaColumnDifference differenceFrom(SchemaColumn column) {
    return SchemaColumnDifference(this, column);
  }

  /// Returns string representation of [ManagedPropertyType].
  static String typeStringForType(ManagedPropertyType type) {
    switch (type) {
      case ManagedPropertyType.integer:
        return "integer";
      case ManagedPropertyType.doublePrecision:
        return "double";
      case ManagedPropertyType.bigInteger:
        return "bigInteger";
      case ManagedPropertyType.boolean:
        return "boolean";
      case ManagedPropertyType.datetime:
        return "datetime";
      case ManagedPropertyType.string:
        return "string";
      case ManagedPropertyType.list:
        return null;
      case ManagedPropertyType.map:
        return null;
      case ManagedPropertyType.document:
        return "document";
    }
    return null;
  }

  /// Returns inverse of [typeStringForType].
  static ManagedPropertyType typeFromTypeString(String type) {
    switch (type) {
      case "integer":
        return ManagedPropertyType.integer;
      case "double":
        return ManagedPropertyType.doublePrecision;
      case "bigInteger":
        return ManagedPropertyType.bigInteger;
      case "boolean":
        return ManagedPropertyType.boolean;
      case "datetime":
        return ManagedPropertyType.datetime;
      case "string":
        return ManagedPropertyType.string;
      case "document":
        return ManagedPropertyType.document;
    }
    return null;
  }

  /// Returns string representation of [DeleteRule].
  static String deleteRuleStringForDeleteRule(DeleteRule rule) {
    switch (rule) {
      case DeleteRule.cascade:
        return "cascade";
      case DeleteRule.nullify:
        return "nullify";
      case DeleteRule.restrict:
        return "restrict";
      case DeleteRule.setDefault:
        return "default";
    }
    return null;
  }

  /// Returns inverse of [deleteRuleStringForDeleteRule].
  static DeleteRule deleteRuleForDeleteRuleString(String rule) {
    switch (rule) {
      case "cascade":
        return DeleteRule.cascade;
      case "nullify":
        return DeleteRule.nullify;
      case "restrict":
        return DeleteRule.restrict;
      case "default":
        return DeleteRule.setDefault;
    }
    return null;
  }

  /// Returns portable representation of this instance.
  Map<String, dynamic> asMap() {
    return {
      "name": name,
      "type": _type,
      "nullable": isNullable,
      "autoincrement": autoincrement,
      "unique": isUnique,
      "defaultValue": defaultValue,
      "primaryKey": isPrimaryKey,
      "relatedTableName": relatedTableName,
      "relatedColumnName": relatedColumnName,
      "deleteRule": _deleteRule,
      "indexed": isIndexed
    };
  }

  @override
  String toString() => "$name (-> $relatedTableName.$relatedColumnName)";
}

/// The difference between two compared [SchemaColumn]s.
///
/// This class is used for comparing database columns for validation and migration.
class SchemaColumnDifference {
  /// Creates a new instance that represents the difference between [expectedColumn] and [actualColumn].
  SchemaColumnDifference(this.expectedColumn, this.actualColumn) {
    if (actualColumn != null && expectedColumn != null) {
      if (actualColumn.isPrimaryKey != expectedColumn.isPrimaryKey) {
        throw SchemaException(
            "Cannot change primary key of '${expectedColumn.table.name}'");
      }

      if (actualColumn.relatedColumnName != expectedColumn.relatedColumnName) {
        throw SchemaException(
            "Cannot change Relationship inverse of '${expectedColumn.table.name}.${expectedColumn.name}'");
      }

      if (actualColumn.relatedTableName != expectedColumn.relatedTableName) {
        throw SchemaException(
            "Cannot change type of '${expectedColumn.table.name}.${expectedColumn.name}'");
      }

      if (actualColumn.type != expectedColumn.type) {
        throw SchemaException(
            "Cannot change type of '${expectedColumn.table.name}.${expectedColumn.name}'");
      }

      if (actualColumn.autoincrement != expectedColumn.autoincrement) {
        throw SchemaException(
            "Cannot change autoincrement behavior of '${expectedColumn.table.name}.${expectedColumn.name}'");
      }

      if (expectedColumn.name?.toLowerCase() !=
          actualColumn.name?.toLowerCase()) {
        _differingProperties.add(_PropertyDifference(
            "name", expectedColumn.name, actualColumn.name));
      }

      if (expectedColumn.isIndexed != actualColumn.isIndexed) {
        _differingProperties.add(_PropertyDifference(
            "isIndexed", expectedColumn.isIndexed, actualColumn.isIndexed));
      }

      if (expectedColumn.isUnique != actualColumn.isUnique) {
        _differingProperties.add(_PropertyDifference(
          "isUnique", expectedColumn.isUnique, actualColumn.isUnique));
      }

      if (expectedColumn.isNullable != actualColumn.isNullable) {
        _differingProperties.add(_PropertyDifference(
            "isNullable", expectedColumn.isNullable, actualColumn.isNullable));
      }

      if (expectedColumn.defaultValue != actualColumn.defaultValue) {
        _differingProperties.add(_PropertyDifference("defaultValue",
            expectedColumn.defaultValue, actualColumn.defaultValue));
      }

      if (expectedColumn.deleteRule != actualColumn.deleteRule) {
        _differingProperties.add(_PropertyDifference(
            "deleteRule", expectedColumn.deleteRule, actualColumn.deleteRule));
      }
    }
  }

  /// The expected column.
  ///
  /// May be null if there is no column expected.
  final SchemaColumn expectedColumn;

  /// The actual column.
  ///
  /// May be null if there is no actual column.
  final SchemaColumn actualColumn;

  /// Whether or not [expectedColumn] and [actualColumn] are different.
  bool get hasDifferences =>
      _differingProperties.isNotEmpty ||
      (expectedColumn == null && actualColumn != null) ||
      (actualColumn == null && expectedColumn != null);

  /// Human-readable list of differences between [expectedColumn] and [actualColumn].
  ///
  /// Empty is there are no differences.
  List<String> get errorMessages {
    if (expectedColumn == null && actualColumn != null) {
      return [
        "Column '${actualColumn.name}' in table '${actualColumn.table.name}' should NOT exist, but is created by migration files"
      ];
    } else if (expectedColumn != null && actualColumn == null) {
      return [
        "Column '${expectedColumn.name}' in table '${expectedColumn.table.name}' should exist, but is NOT created by migration files"
      ];
    }

    return _differingProperties.map((property) {
      return property.getErrorMessage(expectedColumn.table.name, expectedColumn.name);
    }).toList();
  }

  List<_PropertyDifference> _differingProperties = [];
}

class _PropertyDifference {
  _PropertyDifference(this.name, this.expectedValue, this.actualValue);

  final String name;
  final dynamic expectedValue;
  final dynamic actualValue;

  String getErrorMessage(String actualTableName, String expectedColumnName) {
    return "Column '${expectedColumnName}' in table '${actualTableName}' expected "
      "'$expectedValue' for '$name', but migration files yield '$actualValue'";
  }
}
