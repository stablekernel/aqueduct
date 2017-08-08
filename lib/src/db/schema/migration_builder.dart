import 'schema.dart';

class MigrationBuilder {
  static String sourceForSchemaUpgrade(
      Schema existingSchema, Schema newSchema, int version, {List<String> changeList}) {
    var builder = new StringBuffer();
    builder.writeln("import 'package:aqueduct/aqueduct.dart';");
    builder.writeln("import 'dart:async';");
    builder.writeln("");
    builder.writeln("class Migration$version extends Migration {");
    builder.writeln("  Future upgrade() async {");

    var diff = existingSchema.differenceFrom(newSchema);

    // Grab tables from dependencyOrderedTables to reuse ordering behavior
    newSchema.dependencyOrderedTables
        .where((t) => diff.tableNamesToAdd.contains(t.name))
        .forEach((t) {
      changeList?.add("Adding table '${t.name}'");
      builder.writeln(MigrationBuilder.createTableString(t, "    "));
    });

    existingSchema.dependencyOrderedTables.reversed
        .where((t) => diff.tableNamesToDelete.contains(t.name))
        .forEach((t) {
      changeList?.add("Deleting table '${t.name}'");
      builder.writeln(MigrationBuilder.deleteTableString(t.name, "    "));
    });

    diff.differingTables
        .where((tableDiff) => tableDiff.expectedTable != null && tableDiff.actualTable != null)
        .forEach((tableDiff) {
      tableDiff.columnNamesToAdd
          .forEach((columnName) {
        changeList?.add("Adding column '$columnName' to table '${tableDiff.actualTable.name}'");
        builder.writeln(MigrationBuilder.addColumnString(tableDiff.actualTable.name, tableDiff.actualTable.columnForName(columnName), "    "));
      });

      tableDiff.columnNamesToDelete
          .forEach((columnName) {
        changeList?.add("Deleting column '$columnName' from table '${tableDiff.actualTable.name}'");
        builder.writeln(MigrationBuilder.deleteColumnString(tableDiff.actualTable.name, columnName, "    "));
      });

      tableDiff.differingColumns
          .where((columnDiff) => columnDiff.expectedColumn != null && columnDiff.actualColumn != null)
          .forEach((columnDiff) {
        changeList?.add("Modifying column '${columnDiff.actualColumn.name}' in table '${tableDiff.actualTable.name}'");
        builder.writeln(MigrationBuilder.alterColumnString(tableDiff.actualTable.name, columnDiff.expectedColumn, columnDiff.actualColumn, "    "));
      });
    });

    builder.writeln("  }");
    builder.writeln("");
    builder.writeln("  Future downgrade() async {");
    builder.writeln("  }");
    builder.writeln("  Future seed() async {");
    builder.writeln("  }");
    builder.writeln("}");

    return builder.toString();
  }

  static String createTableString(SchemaTable table, String spaceOffset,
      {bool temporary: false}) {
    var builder = new StringBuffer();
    builder.writeln(
        '${spaceOffset}database.createTable(new SchemaTable("${table.name}", [');
    table.columns.forEach((col) {
      builder.writeln("$spaceOffset    ${_newColumnString(col, "  ")},");
    });
    builder.writeln("$spaceOffset  ],");

    if (table.uniqueColumnSet != null) {
      var set = table.uniqueColumnSet.map((p) => '"$p"').join(",");
      builder.writeln("${spaceOffset}  uniqueColumnSet: [$set],");
    }

    builder.writeln('$spaceOffset));');

    return builder.toString();
  }

  static String deleteTableString(String tableName, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.deleteTable("$tableName");');

    return builder.toString();
  }

  static String alterTableString(SchemaTable previousTable, SchemaTable updatedTable, String spaceOffset) {
    var builder = new StringBuffer();

    if ((previousTable.uniqueColumnSet == null && updatedTable.uniqueColumnSet != null)
    || (previousTable.uniqueColumnSet != null && updatedTable.uniqueColumnSet == null)) {

    } else if (previousTable.uniqueColumnSet)

  }

  static String addColumnString(String tableName, SchemaColumn column, String spaceOffset) {
    var builder = new StringBuffer();

    if (column.isNullable || column.defaultValue != null) {
      builder.writeln(
          '${spaceOffset}database.addColumn("$tableName", ${_newColumnString(column, "")});');
    } else {
      builder.writeln(
          '${spaceOffset}database.addColumn("$tableName", ${_newColumnString(column, "")}, unencodedInitialValue: <<set>>);');
    }

    return builder.toString();
  }

  static String deleteColumnString(String tableName, String columnName, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.deleteColumn("$tableName", "$columnName");');

    return builder.toString();
  }

  static String alterColumnString(String tableName, SchemaColumn previousColumn, SchemaColumn updatedColumn, String spaceOffset) {
    if (updatedColumn.isPrimaryKey != previousColumn.isPrimaryKey) {
      throw new SchemaException("Cannot change primary key of '$tableName'");
    }

    if (updatedColumn.relatedColumnName != previousColumn.relatedColumnName) {
      throw new SchemaException("Cannot change ManagedRelationship inverse of '$tableName.${previousColumn.name}'");
    }

    if (updatedColumn.relatedTableName != previousColumn.relatedTableName) {
      throw new SchemaException("Cannot change type of '$tableName.${previousColumn.name}'");
    }

    if (updatedColumn.type != previousColumn.type) {
      throw new SchemaException("Cannot change type of '$tableName.${previousColumn.name}'");
    }

    if (updatedColumn.autoincrement != previousColumn.autoincrement) {
      throw new SchemaException("Cannot change autoincrement behavior of '$tableName.${previousColumn.name}'");
    }

    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.alterColumn("$tableName", "${previousColumn.name}", (c) {');

    if (previousColumn.isIndexed != updatedColumn.isIndexed) {
      builder.writeln("$spaceOffset  c.isIndexed = ${updatedColumn.isIndexed};");
    }

    if (previousColumn.isUnique != updatedColumn.isUnique) {
      builder.writeln("$spaceOffset  c.isUnique = ${updatedColumn.isUnique};");
    }

    if (previousColumn.defaultValue != updatedColumn.defaultValue) {
      builder.writeln("$spaceOffset  c.defaultValue = \"${updatedColumn.defaultValue}\";");
    }

    if (previousColumn.deleteRule != updatedColumn.deleteRule) {
      builder.writeln("$spaceOffset  c.deleteRule = ${updatedColumn.deleteRule};");
    }

    if (previousColumn.isNullable != updatedColumn.isNullable) {
      builder.writeln("$spaceOffset  c.isNullable = ${updatedColumn.isNullable};");
    }

    if(previousColumn.isNullable == true && updatedColumn.isNullable == false && updatedColumn.defaultValue == null) {
      builder.writeln("$spaceOffset}, unencodedInitialValue: <<set>>);");
    } else {
      builder.writeln("$spaceOffset});");
    }

    return builder.toString();
  }

  static String _newColumnString(SchemaColumn column, String spaceOffset) {
    var builder = new StringBuffer();
    if (column.relatedTableName != null) {
      builder.write(
          '${spaceOffset}new SchemaColumn.relationship("${column.name}", ${column.type}');
      builder.write(", relatedTableName: \"${column.relatedTableName}\"");
      builder.write(", relatedColumnName: \"${column.relatedColumnName}\"");
      builder.write(", rule: ${column.deleteRule}");
    } else {
      builder.write(
          '${spaceOffset}new SchemaColumn("${column.name}", ${column.type}');
      if (column.isPrimaryKey) {
        builder.write(", isPrimaryKey: true");
      } else {
        builder.write(", isPrimaryKey: false");
      }
      if (column.autoincrement) {
        builder.write(", autoincrement: true");
      } else {
        builder.write(", autoincrement: false");
      }
      if (column.defaultValue != null) {
        builder.write(', defaultValue: "${column.defaultValue}"');
      }
      if (column.isIndexed) {
        builder.write(", isIndexed: true");
      } else {
        builder.write(", isIndexed: false");
      }
    }

    if (column.isNullable) {
      builder.write(", isNullable: true");
    } else {
      builder.write(", isNullable: false");
    }
    if (column.isUnique) {
      builder.write(", isUnique: true");
    } else {
      builder.write(", isUnique: false");
    }

    builder.write(")");
    return builder.toString();
  }
}
