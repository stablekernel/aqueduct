import 'schema.dart';
import '../managed/managed.dart';

/// Represents a database table for a [Schema].
///
/// Use this class during migration to add, delete and modify tables in a schema.
class SchemaTable {
  SchemaTable(this.name, this.columns, {List<String> uniqueColumnSetNames}) {
    this.uniqueColumnSet = uniqueColumnSetNames;
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
    columns = otherTable.columns
        .map((col) => new SchemaColumn.from(col))
        .toList();
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

  List<String> get uniqueColumnSet => _uniqueColumnSet;
  set uniqueColumnSet(List<String> columns) {
    _uniqueColumnSet = columns;
    _uniqueColumnSet?.sort((String a, String b) => a.compareTo(b));
  }
  List<String> _uniqueColumnSet;

  List<SchemaColumn> columns;

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  /// The differences between two tables.
  SchemaTableDifference differenceFrom(SchemaTable table) {
    return new SchemaTableDifference(this, table);
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

  String get migrationCreateCommand {
    var builder = new StringBuffer();
    builder.writeln(
        'database.createTable(new SchemaTable("$name", [');
    columns.forEach((col) {
      builder.writeln("${_newColumnString(col, "  ")},");
    });
    builder.writeln("],");

    if (uniqueColumnSet != null) {
      var set = uniqueColumnSet.map((p) => '"$p"').join(",");
      builder.writeln("uniqueColumnSetNames: [$set],");
    }

    builder.writeln('));');

    return builder.toString();
  }

  String get migrationDeleteCommand {
    return 'database.deleteTable("$name");';
  }
}

class SchemaTableDifference {
  SchemaTableDifference(this.expectedTable, this.actualTable) {
    for (var expectedColumn in expectedTable.columns) {
      var actualColumn = actualTable[expectedColumn.name];
      if (actualColumn == null) {
        differingColumns.add(
            new SchemaColumnDifference(expectedColumn, null));
      } else {
        var diff = expectedColumn.differenceFrom(actualColumn);
        if (diff.hasDifferences) {
          differingColumns.add(diff);
        }
      }
    }

    differingColumns.addAll(actualTable.columns
        .where((t) => expectedTable[t.name] == null)
        .map((unexpectedColumn) {
      return new SchemaColumnDifference(null, unexpectedColumn);
    }));
  }

  bool get hasDifferences =>
      differingColumns.length > 0 ||
          expectedTable?.name?.toLowerCase() != actualTable?.name?.toLowerCase() ||
          (expectedTable == null && actualTable != null) ||
          (actualTable == null && expectedTable != null) ||
          uniqueSetDifference.hasDifferences;

  List<String> get errorMessages {
    if (expectedTable == null && actualTable != null) {
      return [
        "Table '$actualTable' should NOT exist, but is created by migration files."
      ];
    } else if (expectedTable != null && actualTable == null) {
      return [
        "Table '$expectedTable' should exist, but it is NOT created by migration files."
      ];
    }

    var diffs = differingColumns
        .expand((diff) => diff.errorMessages(this))
        .toList();
    diffs.addAll(uniqueSetDifference.errorMessages(this));

    return diffs;
  }

  SchemaTable expectedTable;
  SchemaTable actualTable;
  SchemaTableUniqueSetDifference uniqueSetDifference;
  List<SchemaColumnDifference> differingColumns = [];

  List<String> get columnNamesToAdd =>
      differingColumns
          .where((diff) => diff.expectedColumn == null && diff.actualColumn != null)
          .map((diff) => diff.actualColumn.name)
          .toList();

  List<String> get columnNamesToDelete =>
      differingColumns
          .where((diff) => diff.expectedColumn != null && diff.actualColumn == null)
          .map((diff) => diff.expectedColumn.name)
          .toList();

  String generateUpgradeSource({List<String> changeList}) {
    var builder = new StringBuffer();

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

    return builder.toString();
  }
}

class SchemaTableUniqueSetDifference {
  SchemaTableUniqueSetDifference(this.expectedColumnNames, this.actualColumnNames) {
    expectedColumnNames ??= [];
    actualColumnNames ??= [];
  }

  List<String> expectedColumnNames;
  List<String> actualColumnNames;

  bool get hasDifferences {
    if (expectedColumnNames.length != actualColumnNames.length) {
      return true;
    }

    return !expectedColumnNames.every((s) => actualColumnNames.contains(s));
  }

  List<String> errorMessages(SchemaTableDifference tableDiff) {
    if (expectedColumnNames.isEmpty && actualColumnNames.isNotEmpty) {
      return ["Multi-column unique constraint on table '${tableDiff.expectedTable.name}' "
          "should NOT exist, but is created by migration files."];
    } else if (expectedColumnNames.isNotEmpty && actualColumnNames.isEmpty) {
      return ["Multi-column unique constraint on table '${tableDiff.expectedTable.name}' "
          "should exist, but it is NOT created by migration files."];
    }

    if (hasDifferences) {
      var expectedColumns = expectedColumnNames.map((c) => "'$c'").join(", ");
      var actualColumns = actualColumnNames.map((c) => "'$c'").join(", ");

      return ["Multi-column unique constraint on table '${tableDiff.expectedTable.name}' "
          "is expected to be for properties $expectedColumns, but is actually $actualColumns"];
    }

    return [];
  }
}