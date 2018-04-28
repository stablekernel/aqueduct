import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:postgres/postgres.dart';

/// Common interface for values that can be mapped to/from a database.
abstract class Returnable {}

class ColumnBuilder extends Returnable {
  ColumnBuilder(this.table, this.property, {this.documentKeyPath});

  static List<ColumnBuilder> fromKeys(TableBuilder table, List<KeyPath> keys) {
    keys ??= [];

    final entity = table.entity;

    // Ensure the primary key is always available and at 0th index.
    var primaryKeyIndex;
    for (var i = 0; i < keys.length; i++) {
      final firstElement = keys[i].path.first;
      if (firstElement is ManagedAttributeDescription && firstElement.isPrimaryKey) {
        primaryKeyIndex = i;
        break;
      }
    }

    if (primaryKeyIndex == null) {
      keys.insert(0, new KeyPath(entity.primaryKeyAttribute));
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, new KeyPath(entity.primaryKeyAttribute));
    }

    return keys.map((key) {
      return new ColumnBuilder(table, propertyForName(entity, key.path.first.name), documentKeyPath: key.dynamicElements);
    }).toList();
  }

  static ManagedPropertyDescription propertyForName(ManagedEntity entity, String propertyName) {
    var property = entity.properties[propertyName];

    if (property == null) {
      throw new ArgumentError(
          "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'.");
    }

    if (property is ManagedRelationshipDescription && property.relationshipType != ManagedRelationshipType.belongsTo) {
      throw new ArgumentError(
          "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'. "
              "'$propertyName' recognized as ORM relationship, use 'Query.join' instead.");
    }

    return property;
  }

  static Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double,
    ManagedPropertyType.document: PostgreSQLDataType.json
  };

  static Map<PredicateOperator, String> symbolTable = {
    PredicateOperator.lessThan: "<",
    PredicateOperator.greaterThan: ">",
    PredicateOperator.notEqual: "!=",
    PredicateOperator.lessThanEqualTo: "<=",
    PredicateOperator.greaterThanEqualTo: ">=",
    PredicateOperator.equalTo: "="
  };

  final TableBuilder table;
  final ManagedPropertyDescription property;
  final List<String> documentKeyPath;

  dynamic convertValueForStorage(dynamic value) {
    if (property is ManagedAttributeDescription) {
      ManagedAttributeDescription p = property;
      if (p.isEnumeratedValue) {
        return property.convertToPrimitiveValue(value);
      } else if (p.type.kind == ManagedPropertyType.document) {
        if (value is Document) {
          return value.data;
        } else if (value is Map || value is List) {
          return value;
        }

        throw new ArgumentError("Invalid data type for 'Document'. Must be 'Document', 'Map', or 'List'.");
      }
    }

    return value;
  }

  dynamic convertValueFromStorage(dynamic value) {
    if (value == null) {
      return null;
    }

    if (property is ManagedAttributeDescription) {
      ManagedAttributeDescription p = property;
      if (p.isEnumeratedValue) {
        return property.convertFromPrimitiveValue(value);
      } else if (p.type.kind == ManagedPropertyType.document) {
        return new Document(value);
      }
    }

    return value;
  }

  String get sqlTypeSuffix {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[property.type.kind]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  String sqlColumnName({bool withTypeSuffix: false, bool withTableNamespace: false, String withPrefix}) {
    var name = property.name;

    if (property is ManagedRelationshipDescription) {
      var relatedPrimaryKey = (property as ManagedRelationshipDescription).destinationEntity.primaryKey;
      name = "${name}_$relatedPrimaryKey";
    } else if (documentKeyPath != null) {
      final keys = documentKeyPath.map((k) => k is String ? "'$k'" : k).join("->");
      name = "$name->$keys";
    }

    if (withTypeSuffix) {
      name = "$name$sqlTypeSuffix";
    }

    if (withTableNamespace) {
      return "${table.sqlTableReference}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}

