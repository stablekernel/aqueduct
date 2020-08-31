import 'package:aqueduct/aqueduct.dart';

abstract class MySqlSchemaGenerator {
  String get versionTableName => "_aqueduct_version_mysql";

  String get databaseName;

  List<String> createTable(SchemaTable table, {bool isTemporary = false}) {
    var commands = <String>[];

    // "select count(*)  from information_schema.TABLES t where t.TABLE_SCHEMA ='$databaseName' and t.TABLE_NAME ='${table.name}'"

    // Create table command
    var columnString = table.columns.map(_columnStringForColumn).join(",");

    commands.add(
        "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE `${table.name}` ($columnString)");

    var indexCommands = table.columns
        .where((col) =>
            col.isIndexed && !col.isPrimaryKey) // primary keys are auto-indexed
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);
    commands.addAll(indexCommands);

    commands.addAll(table.columns
        .where((sc) => sc.isForeignKey)
        .map((col) => _addConstraintsForColumn(table.name, col))
        .expand((commands) => commands));

    if (table.uniqueColumnSet != null) {
      commands.addAll(addTableUniqueColumnSet(table));
    }
    return commands;
  }

  List<String> renameTable(SchemaTable table, String name) {
    // Must rename indices, constraints, etc.
    throw UnsupportedError("renameTable is not yet supported.");
  }

  List<String> deleteTable(SchemaTable table) {
    return ["DROP TABLE ${table.name}"];
  }

  List<String> addTableUniqueColumnSet(SchemaTable table) {
    var colNames = table.uniqueColumnSet
        .map((name) => _columnNameForColumn(table[name]))
        .join(",");
    return [
      "CREATE UNIQUE INDEX ${table.name}_unique_idx ON `${table.name}` ($colNames)"
    ];
  }

  List<String> deleteTableUniqueColumnSet(SchemaTable table) {
    return ["DROP INDEX IF EXISTS ${table.name}_unique_idx"];
  }

  List<String> addColumn(SchemaTable table, SchemaColumn column,
      {String unencodedInitialValue}) {
    var commands = <String>[];

    if (unencodedInitialValue != null) {
      column.defaultValue = unencodedInitialValue;
      commands.addAll([
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}",
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP DEFAULT"
      ]);
    } else {
      commands.addAll([
        "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}"
      ]);
    }

    if (column.isIndexed) {
      commands.addAll(addIndexToColumn(table, column));
    }

    if (column.isForeignKey) {
      commands.addAll(_addConstraintsForColumn(table.name, column));
    }
    print(commands);
    return commands;
  }

  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    return [
      "ALTER TABLE ${table.name} DROP COLUMN ${_columnNameForColumn(column)} ${column.relatedColumnName != null ? "CASCADE" : "RESTRICT"}"
    ];
  }

  List<String> renameColumn(
      SchemaTable table, SchemaColumn column, String name) {
    // Must rename indices, constraints, etc.
    throw UnsupportedError("renameColumn is not yet supported.");
  }

  List<String> alterColumnNullability(
      SchemaTable table, SchemaColumn column, String unencodedInitialValue) {
    if (column.isNullable) {
      return [
        "ALTER TABLE ${table.name} CHANGE COLUMN ${_columnNameForColumn(column)} DROP NOT NULL"
      ];
    } else {
      if (unencodedInitialValue != null) {
        return [
          "UPDATE ${table.name} SET ${_columnNameForColumn(column)}=$unencodedInitialValue WHERE ${_columnNameForColumn(column)} IS NULL",
          "ALTER TABLE ${table.name} CHANGE COLUMN ${_columnNameForColumn(column)} SET NOT NULL",
        ];
      } else {
        return [
          "ALTER TABLE ${table.name} CHANGE COLUMN ${_columnNameForColumn(column)} SET NOT NULL"
        ];
      }
    }
  }

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    if (column.isUnique) {
      return ["ALTER TABLE ${table.name} ADD UNIQUE (${column.name})"];
    } else {
      return [
        // "ALTER TABLE ${table.name} DROP CONSTRAINT ${_uniqueKeyName(table.name, column)}"
        "ALTER TABLE ${table.name} DROP INDEX `${column.name}`"
      ];
    }
  }

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    if (column.defaultValue != null) {
      String defVal = column.defaultValue;
      if (column.typeString == "string" || column.typeString == "datetime") {
        defVal = "'${defVal}'";
      }
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} SET DEFAULT $defVal"
      ];
    } else {
      return [
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP DEFAULT"
      ];
    }
  }

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    var allCommands = <String>[];
    allCommands.add(
        "ALTER TABLE ${table.name} DROP CONSTRAINT ${_foreignKeyName(table.name, column)}");
    allCommands.addAll(_addConstraintsForColumn(table.name, column));
    return allCommands;
  }

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    return [
      "CREATE INDEX `${_indexNameForColumn(table.name, column)}` ON `${table.name}` (`${_columnNameForColumn(column)}`)"
    ];
  }

  List<String> renameIndex(
      SchemaTable table, SchemaColumn column, String newIndexName) {
    var existingIndexName = _indexNameForColumn(table.name, column);
    return ["ALTER INDEX $existingIndexName RENAME TO $newIndexName"];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${_indexNameForColumn(table.name, column)} ON `${table.name}`"
    ];
  }

  ////

  String _uniqueKeyName(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_key";
  }

  String _foreignKeyName(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_fkey";
  }

  List<String> _addConstraintsForColumn(String tableName, SchemaColumn column) {
    return [
      "ALTER TABLE  $tableName ADD FOREIGN KEY fk_name(${_columnNameForColumn(column)}) "
          "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) "
          "ON DELETE ${_deleteRuleStringForDeleteRule(SchemaColumn.deleteRuleStringForDeleteRule(column.deleteRule))}"
    ];
  }

  String _indexNameForColumn(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_idx";
  }

  String _columnStringForColumn(SchemaColumn col) {
    var elements = ["`${_columnNameForColumn(col)}`", _mySqlTypeForColumn(col)];

    if (col.isPrimaryKey) {
      elements.add("PRIMARY KEY");
    } else {
      elements.add(col.isNullable ? "NULL" : "NOT NULL");
      if (col.defaultValue != null) {
        elements.add("DEFAULT ${col.defaultValue}");
      }
      if (col.isUnique) {
        elements.add("UNIQUE KEY");
      }
    }

    return elements.join(" ");
  }

  String _columnNameForColumn(SchemaColumn column) {
    if (column.relatedColumnName != null) {
      return "${column.name}_${column.relatedColumnName}";
    }

    return column.name;
  }

  String _deleteRuleStringForDeleteRule(String deleteRule) {
    switch (deleteRule) {
      case "cascade":
        return "CASCADE";
      case "restrict":
        return "RESTRICT";
      case "default":
        return "SET DEFAULT";
      case "nullify":
        return "SET NULL";
    }

    return null;
  }

  String _mySqlTypeForColumn(SchemaColumn t) {
    switch (t.typeString) {
      case "integer":
        {
          if (t.autoincrement) {
            return "INT AUTO_INCREMENT";
          }
          return "INT";
        }
        break;
      case "bigInteger":
        {
          if (t.autoincrement) {
            return "BIGINT AUTO_INCREMENT";
          }
          return "BIGINT";
        }
        break;
      case "string":
        if (t.size != null) {
          return "VARCHAR(${t.size})";
        }
        if (t.isUnique || t.isPrimaryKey || t.isForeignKey || t.isIndexed) {
          return "VARCHAR(50)";
        }
        return "VARCHAR(250)";
      // return "TEXT";
      case "datetime":
        return "DATETIME";
      case "boolean":
        return "BOOLEAN";
      case "double":
        return "DOUBLE";
      case "decimal":
        return "DECIMAL";
      case "document":
        return "JSON";
    }

    return null;
  }

  SchemaTable get versionTable {
    return SchemaTable(versionTableName, [
      SchemaColumn.empty()
        ..name = "versionNumber"
        ..type = ManagedPropertyType.integer
        ..isUnique = true,
      SchemaColumn.empty()
        ..name = "dateOfUpgrade"
        ..type = ManagedPropertyType.datetime,
    ]);
  }
}
