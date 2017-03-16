import 'schema.dart';

class MigrationBuilder {
  static String createTableString(SchemaTable table, String spaceOffset,
      {bool temporary: false}) {
    var builder = new StringBuffer();
    builder.writeln(
        '${spaceOffset}database.createTable(new SchemaTable("${table.name}", [');
    table.columns.forEach((col) {
      builder.writeln("${spaceOffset}${_newColumnString(col, "  ")},");
    });
    builder.writeln('${spaceOffset}]));');

    return builder.toString();
  }

  static String deleteTableString(String tableName, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.deleteTable("$tableName");');

    return builder.toString();
  }

  static String addColumnString(String tableName, SchemaColumn column, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.addColumn("${tableName}", ${_newColumnString(column, "")});');

    return builder.toString();
  }

  static String deleteColumnString(String tableName, String columnName, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.deleteColumn("${tableName}", "${columnName}");');

    return builder.toString();
  }

  static String alterColumnString(String tableName, SchemaColumn previousColumn, SchemaColumn updatedColumn, String spaceOffset) {
    var builder = new StringBuffer();

    builder.writeln(
        '${spaceOffset}database.alterColumn("${tableName}", "${previousColumn.name}", (c) {');

    if (previousColumn.name != updatedColumn.name) {
      builder.writeln('$spaceOffset  c.name = "${updatedColumn.name}";');
    }

    if (previousColumn.type != updatedColumn.type) {
      builder.writeln("$spaceOffset  c.type = ${updatedColumn.type};");
    }

    if (previousColumn.isIndexed != updatedColumn.isIndexed) {
      builder.writeln("$spaceOffset  c.isIndexed = ${updatedColumn.isIndexed};");
    }

    if (previousColumn.isNullable != updatedColumn.isNullable) {
      builder.writeln("$spaceOffset  c.isNullable = ${updatedColumn.isNullable};");
    }

    if (previousColumn.autoincrement != updatedColumn.autoincrement) {
      builder.writeln("$spaceOffset  c.autoincrement = ${updatedColumn.autoincrement};");
    }

    if (previousColumn.isUnique != updatedColumn.isUnique) {
      builder.writeln("$spaceOffset  c.isUnique = ${updatedColumn.isUnique};");
    }

    if (previousColumn.defaultValue != updatedColumn.defaultValue) {
      builder.writeln("$spaceOffset  c.defaultValue = ${updatedColumn.defaultValue};");
    }

    if (previousColumn.isPrimaryKey != updatedColumn.isPrimaryKey) {
      builder.writeln("$spaceOffset  c.isPrimaryKey = ${updatedColumn.isPrimaryKey};");
    }

    if (previousColumn.relatedTableName != updatedColumn.relatedTableName) {
      builder.writeln("$spaceOffset  c.relatedTableName = ${updatedColumn.relatedTableName};");
    }

    if (previousColumn.relatedColumnName != updatedColumn.relatedColumnName) {
      builder.writeln("$spaceOffset  c.relatedColumnName = ${updatedColumn.relatedColumnName};");
    }

    if (previousColumn.deleteRule != updatedColumn.deleteRule) {
      builder.writeln("$spaceOffset  c.deleteRule = ${updatedColumn.deleteRule};");
    }

    builder.writeln("});");

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