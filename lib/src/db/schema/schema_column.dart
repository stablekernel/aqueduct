import 'dart:mirrors';

import '../managed/managed.dart';
import 'schema.dart';

/// Represents a database column for a [SchemaTable].
///
/// Use this class during migration to add, delete and modify columns.
class SchemaColumn {
  SchemaColumn(this.name, ManagedPropertyType t,
      {this.isIndexed: false,
      this.isNullable: false,
      this.autoincrement: false,
      this.isUnique: false,
      this.defaultValue,
      this.isPrimaryKey: false}) {
    _type = typeStringForType(t);
  }

  SchemaColumn.relationship(this.name, ManagedPropertyType t,
      {this.isNullable: true,
      this.isUnique: false,
      this.relatedTableName,
      this.relatedColumnName,
      ManagedRelationshipDeleteRule rule:
          ManagedRelationshipDeleteRule.nullify}) {
    isIndexed = true;
    _type = typeStringForType(t);
    _deleteRule = deleteRuleStringForDeleteRule(rule);
  }

  SchemaColumn.fromEntity(
      ManagedEntity entity, ManagedPropertyDescription desc) {
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

    _type = typeStringForType(desc.type);
    isNullable = desc.isNullable;
    autoincrement = desc.autoincrement;
    isUnique = desc.isUnique;
    isIndexed = desc.isIndexed;
  }

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

  SchemaColumn.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    _type = map["type"];
    isIndexed = map["indexed"];
    isNullable = map["nullable"];
    autoincrement = map["autoincrement"];
    isUnique = map["unique"];
    defaultValue = map["defaultValue"];
    isPrimaryKey = map["primaryKey"];
    relatedTableName = map["relatedTableName"];
    relatedColumnName = map["relatedColumnName"];
    _deleteRule = map["deleteRule"];
  }

  SchemaColumn.empty();

  String name;
  SchemaTable table;
  String _type;

  String get typeString => _type;

  ManagedPropertyType get type => typeFromTypeString(_type);
  set type(ManagedPropertyType t) {
    _type = typeStringForType(t);
  }

  bool isIndexed = false;
  bool isNullable = false;
  bool autoincrement = false;
  bool isUnique = false;
  String defaultValue;
  bool isPrimaryKey = false;

  String relatedTableName;
  String relatedColumnName;
  String _deleteRule;
  ManagedRelationshipDeleteRule get deleteRule =>
      deleteRuleForDeleteRuleString(_deleteRule);
  set deleteRule(ManagedRelationshipDeleteRule t) {
    _deleteRule = deleteRuleStringForDeleteRule(t);
  }

  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  /// The differences between two columns.
  SchemaColumnDifference differenceFrom(SchemaColumn column) {
    return new SchemaColumnDifference(this, column);
  }

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
      case ManagedPropertyType.transientList:
        return null;
      case ManagedPropertyType.transientMap:
        return null;
    }
    return null;
  }

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
    }
    return null;
  }

  static String deleteRuleStringForDeleteRule(
      ManagedRelationshipDeleteRule rule) {
    switch (rule) {
      case ManagedRelationshipDeleteRule.cascade:
        return "cascade";
      case ManagedRelationshipDeleteRule.nullify:
        return "nullify";
      case ManagedRelationshipDeleteRule.restrict:
        return "restrict";
      case ManagedRelationshipDeleteRule.setDefault:
        return "default";
    }
    return null;
  }

  static ManagedRelationshipDeleteRule deleteRuleForDeleteRuleString(
      String rule) {
    switch (rule) {
      case "cascade":
        return ManagedRelationshipDeleteRule.cascade;
      case "nullify":
        return ManagedRelationshipDeleteRule.nullify;
      case "restrict":
        return ManagedRelationshipDeleteRule.restrict;
      case "default":
        return ManagedRelationshipDeleteRule.setDefault;
    }
    return null;
  }

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
  String toString() => "$name $relatedTableName";

  String get source {
    var builder = new StringBuffer();
    if (relatedTableName != null) {
      builder.write(
          'new SchemaColumn.relationship("${name}", ${type}');
      builder.write(", relatedTableName: \"${relatedTableName}\"");
      builder.write(", relatedColumnName: \"${relatedColumnName}\"");
      builder.write(", rule: ${deleteRule}");
    } else {
      builder.write(
          'new SchemaColumn("${name}", ${type}');
      if (isPrimaryKey) {
        builder.write(", isPrimaryKey: true");
      } else {
        builder.write(", isPrimaryKey: false");
      }
      if (autoincrement) {
        builder.write(", autoincrement: true");
      } else {
        builder.write(", autoincrement: false");
      }
      if (defaultValue != null) {
        builder.write(', defaultValue: "${defaultValue}"');
      }
      if (isIndexed) {
        builder.write(", isIndexed: true");
      } else {
        builder.write(", isIndexed: false");
      }
    }

    if (isNullable) {
      builder.write(", isNullable: true");
    } else {
      builder.write(", isNullable: false");
    }
    if (isUnique) {
      builder.write(", isUnique: true");
    } else {
      builder.write(", isUnique: false");
    }

    builder.write(")");
    return builder.toString();
  }
}


class SchemaColumnDifference {
  static const List<Symbol> symbols = const [
    #name,
    #isIndexed,
    #type,
    #isNullable,
    #autoincrement,
    #isUnique,
    #defaultValue,
    #isPrimaryKey,
    #relatedTableName,
    #relatedColumnName,
    #deleteRule
  ];

  SchemaColumnDifference(this.expectedColumn, this.actualColumn) {
    if (actualColumn != null && expectedColumn != null) {
      var expectedColumnRefl = reflect(expectedColumn);
      var actualColumnRefl = reflect(actualColumn);

      symbols.forEach((sym) {
        var expectedValue = expectedColumnRefl.getField(sym).reflectee;
        var actualValue = actualColumnRefl.getField(sym).reflectee;
        if (expectedValue is String) {
          expectedValue = (expectedValue as String)?.toLowerCase();
          actualValue = (actualValue as String)?.toLowerCase();
        }

        if (expectedValue != actualValue) {
          differingProperties.add(MirrorSystem.getName(sym));
        }
      });
    }
  }

  final SchemaColumn expectedColumn;
  final SchemaColumn actualColumn;

  List<String> differingProperties = [];

  bool get hasDifferences =>
      differingProperties.length > 0 ||
          (expectedColumn == null && actualColumn != null) ||
          (actualColumn == null && expectedColumn != null);

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

    return differingProperties.map((propertyName) {
      var expectedValue =
          reflect(expectedColumn).getField(new Symbol(propertyName)).reflectee;
      var actualValue =
          reflect(actualColumn).getField(new Symbol(propertyName)).reflectee;

      return "Column '${expectedColumn.name}' in table '${actualColumn.table.name}' expected "
          "'$expectedValue' for '$propertyName', but migration files yield '$actualValue'";
    }).toList();
  }

  String generateUpgradeSource({List<String> changeList}) {
    if (actualColumn.isPrimaryKey != expectedColumn.isPrimaryKey) {
      throw new SchemaException("Cannot change primary key of '${expectedColumn.table.name}'");
    }

    if (actualColumn.relatedColumnName != expectedColumn.relatedColumnName) {
      throw new SchemaException("Cannot change ManagedRelationship inverse of '${expectedColumn.table.name}.${expectedColumn.name}'");
    }

    if (actualColumn.relatedTableName != expectedColumn.relatedTableName) {
      throw new SchemaException("Cannot change type of '${expectedColumn.table.name}.${expectedColumn.name}'");
    }

    if (actualColumn.type != expectedColumn.type) {
      throw new SchemaException("Cannot change type of '${expectedColumn.table.name}.${expectedColumn.name}'");
    }

    if (actualColumn.autoincrement != expectedColumn.autoincrement) {
      throw new SchemaException("Cannot change autoincrement behavior of '${expectedColumn.table.name}.${expectedColumn.name}'");
    }

    var builder = new StringBuffer();

    builder.writeln(
        'database.alterColumn("${expectedColumn.table.name}", "${expectedColumn.name}", (c) {');

    if (expectedColumn.isIndexed != actualColumn.isIndexed) {
      builder.writeln("c.isIndexed = ${actualColumn.isIndexed};");
    }

    if (expectedColumn.isUnique != actualColumn.isUnique) {
      builder.writeln("c.isUnique = ${actualColumn.isUnique};");
    }

    if (expectedColumn.defaultValue != actualColumn.defaultValue) {
      builder.writeln("c.defaultValue = \"${actualColumn.defaultValue}\";");
    }

    if (expectedColumn.deleteRule != actualColumn.deleteRule) {
      builder.writeln("c.deleteRule = ${actualColumn.deleteRule};");
    }

    if (expectedColumn.isNullable != actualColumn.isNullable) {
      builder.writeln("c.isNullable = ${actualColumn.isNullable};");
    }

    if(expectedColumn.isNullable == true && actualColumn.isNullable == false && actualColumn.defaultValue == null) {
      builder.writeln("}, unencodedInitialValue: <<set>>);");
    } else {
      builder.writeln("});");
    }

    return builder.toString();
  }
}
