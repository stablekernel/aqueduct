import 'schema.dart';
import '../managed/managed.dart';

/// Represents a database table for a [Schema].
///
/// Use this class during migration to add, delete and modify tables in a schema.
class SchemaTable {
  SchemaTable(this.name, this.columns);

  SchemaTable.fromEntity(ManagedEntity entity) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) =>
            (p is ManagedAttributeDescription && !p.isTransient) ||
            (p is ManagedRelationshipDescription &&
                p.relationshipType == ManagedRelationshipType.belongsTo))
        .toList();

    columns = validProperties
        .map((p) => new SchemaColumn.fromEntity(entity, p))
        .toList();
  }

  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    columns =
        otherTable.columns.map((col) => new SchemaColumn.from(col)).toList();
  }

  SchemaTable.empty();

  SchemaTable.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    columns = (map["columns"] as List<Map<String, dynamic>>)
        .map((c) => new SchemaColumn.fromMap(c))
        .toList();
  }

  String name;
  List<SchemaColumn> columns;

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  /// Whether or not two tables match.
  ///
  /// If passing [reasons], the reasons for a mismatch are added to the passed in [List].
  bool matches(SchemaTable table, [List<String> reasons]) {
    var matches = true;

    for (var receiverColumn in columns) {
      var matchingArgColumn = table.columnForName(receiverColumn.name);
      if (matchingArgColumn == null) {
        matches = false;
        reasons?.add(
            "Compared table '${table.name}' does not contain '${receiverColumn.name}', but that column exists in receiver schema.");
      } else {
        var columnReasons = <String>[];
        if (!receiverColumn.matches(matchingArgColumn, columnReasons)) {
          reasons?.addAll(columnReasons
              .map((reason) => reason.replaceAll("\$table", table.name)));
          matches = false;
        }
      }
    }

    if (table.columns.length > columns.length) {
      matches = false;
      var receiverColumnNames =
          columns.map((st) => st.name.toLowerCase()).toList();
      table.columns
          .where((st) => !receiverColumnNames.contains(st.name.toLowerCase()))
          .forEach((st) {
        reasons?.add(
            "Receiver table '${table.name}' does not contain '${st.name}', but that column exists in compared table.");
      });
    }

    return matches;
  }

  void addColumn(SchemaColumn column) {
    if (columnForName(column.name) != null) {
      throw new SchemaException("Column ${column.name} already exists.");
    }

    columns.add(column);
  }

  void renameColumn(SchemaColumn column, String newName) {
    throw new SchemaException("Renaming a column not yet implemented!");

//    if (!columns.contains(column)) {
//      throw new SchemaException("Column ${column.name} does not exist on ${name}.");
//    }
//
//    if (columnForName(newName) != null) {
//      throw new SchemaException("Column ${newName} already exists.");
//    }
//
//    if (column.isPrimaryKey) {
//      throw new SchemaException("May not rename primary key column (${column.name} -> ${newName})");
//    }
//
//    // We also must rename indices
//    column.name = newName;
  }

  void removeColumn(SchemaColumn column) {
    column = columnForName(column.name);
    if (column == null) {
      throw new SchemaException(
          "Column ${column.name} does not exist on ${name}.");
    }

    columns.remove(column);
  }

  void replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    existingColumn = columnForName(existingColumn.name);
    if (existingColumn == null) {
      throw new SchemaException(
          "Column ${existingColumn.name} does not exist on ${name}.");
    }

    var index = columns.indexOf(existingColumn);
    columns[index] = newColumn;
  }

  SchemaColumn columnForName(String name) {
    var lowercaseName = name.toLowerCase();
    return columns.firstWhere((col) => col.name.toLowerCase() == lowercaseName,
        orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {"name": name, "columns": columns.map((c) => c.asMap()).toList()};
  }

  String toString() => name;
}
