import 'schema.dart';
import '../managed/managed.dart';

/// Represents a database table for a [Schema].
///
/// Use this class during migration to add, delete and modify tables in a schema.
class SchemaTable {
  SchemaTable(this.name, this.columns, {List<String> uniqueColumnSet}) {
    this.uniqueColumnSet = uniqueColumnSet;
  }

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

    uniqueColumnSet = entity.uniquePropertySet?.map((p) => p.name)?.toList();
  }

  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    columns =
        otherTable.columns.map((col) => new SchemaColumn.from(col)).toList();
    _uniqueColumnSet = otherTable._uniqueColumnSet;
  }

  SchemaTable.empty();

  SchemaTable.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    columns = (map["columns"] as List<Map<String, dynamic>>)
        .map((c) => new SchemaColumn.fromMap(c))
        .toList();
    uniqueColumnSet = map["unique"];
  }

  String name;

  List<String> _uniqueColumnSet;
  List<String> get uniqueColumnSet => _uniqueColumnSet;
  set uniqueColumnSet(List<String> columns) {
    _uniqueColumnSet = columns;
    _uniqueColumnSet?.sort((String a, String b) => a.compareTo(b));
  }
  List<SchemaColumn> columns;

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  /// The differences between two tables.
  SchemaTableDifference differenceFrom(SchemaTable table) {
    var actualTable = table;
    var differences = new SchemaTableDifference()
      ..expectedTable = this
      ..actualTable = actualTable;

    for (var expectedColumn in columns) {
      var actualColumn = actualTable[expectedColumn.name];
      if (actualColumn == null) {
        differences.differingColumns.add(
            new SchemaColumnDifference()
              ..expectedColumn = expectedColumn
              ..actualColumn = null
        );
      } else {
        var diff = expectedColumn.differenceFrom(actualColumn);
        if (diff.hasDifferences) {
          differences.differingColumns.add(diff);
        }
      }
    }

    differences.differingColumns.addAll(actualTable.columns
        .where((t) => this[t.name] == null)
        .map((unexpectedColumn) {
      return new SchemaColumnDifference()
        ..actualColumn = unexpectedColumn
        ..expectedColumn = null;
    }));

    return differences;
  }

  void addColumn(SchemaColumn column) {
    if (this[column.name] != null) {
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
    column = this[column.name];
    if (column == null) {
      throw new SchemaException(
          "Column ${column.name} does not exist on $name.");
    }

    columns.remove(column);
  }

  void replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    existingColumn = this[existingColumn.name];
    if (existingColumn == null) {
      throw new SchemaException(
          "Column ${existingColumn.name} does not exist on $name.");
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
    return {
      "name": name,
      "columns": columns.map((c) => c.asMap()).toList(),
      "unique": uniqueColumnSet
    };
  }

  @override
  String toString() => name;
}
