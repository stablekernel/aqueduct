import 'schema.dart';
import '../managed/managed.dart';

/// Represents a database table for a [Schema].
///
/// Use this class during migration to add, delete and modify tables in a schema.
class SchemaTable {
  SchemaTable(this.name, List<SchemaColumn> columns, {List<String> uniqueColumnSetNames}) {
    this.uniqueColumnSet = uniqueColumnSetNames;
    _columns = columns;
  }

  SchemaTable.fromEntity(ManagedEntity entity) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) =>
    (p is ManagedAttributeDescription && !p.isTransient) ||
        (p is ManagedRelationshipDescription &&
            p.relationshipType == ManagedRelationshipType.belongsTo))
        .toList();

    _columns = validProperties
        .map((p) => new SchemaColumn.fromEntity(entity, p))
        .toList();

    uniqueColumnSet = entity.uniquePropertySet?.map((p) => p.name)?.toList();
  }

  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    _columns = otherTable.columns
        .map((col) => new SchemaColumn.from(col))
        .toList();
    _uniqueColumnSet = otherTable._uniqueColumnSet;
  }

  SchemaTable.empty();

  SchemaTable.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    _columns = (map["columns"] as List<Map<String, dynamic>>)
        .map((c) => new SchemaColumn.fromMap(c))
        .toList();
    uniqueColumnSet = map["unique"];
  }

  Schema schema;
  String name;

  List<String> get uniqueColumnSet => _uniqueColumnSet;

  set uniqueColumnSet(List<String> columnNames) {
    _uniqueColumnSet = columnNames;
    _uniqueColumnSet?.sort((String a, String b) => a.compareTo(b));
  }

  List<SchemaColumn> get columns => new List.unmodifiable(_columnStorage);

  List<SchemaColumn> _columnStorage;
  List<String> _uniqueColumnSet;

  set _columns(List<SchemaColumn> columns) {
    _columnStorage = columns;
    _columnStorage.forEach((c) => c.table = this);
  }

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  /// The differences between two tables.
  SchemaTableDifference differenceFrom(SchemaTable table) {
    return new SchemaTableDifference(this, table);
  }

  void addColumn(SchemaColumn column) {
    if (this[column.name] != null) {
      throw new SchemaException("Column ${column.name} already exists.");
    }

    _columnStorage.add(column);
    column.table = this;
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

    _columnStorage.remove(column);
    column.table = null;
  }

  void replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    existingColumn = this[existingColumn.name];
    if (existingColumn == null) {
      throw new SchemaException(
          "Column ${existingColumn.name} does not exist on $name.");
    }

    var index = _columnStorage.indexOf(existingColumn);
    _columnStorage[index] = newColumn;
    newColumn.table = this;
    existingColumn.table = null;
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

class SchemaTableDifference {
  SchemaTableDifference(this.expectedTable, this.actualTable) {
    if (expectedTable != null && actualTable != null) {
      for (var expectedColumn in expectedTable.columns) {
        var actualColumn = (actualTable != null ? actualTable[expectedColumn.name] : null);
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

      uniqueSetDifference =
        new SchemaTableUniqueSetDifference(expectedTable, actualTable);
    }
  }

  final SchemaTable expectedTable;
  final SchemaTable actualTable;

  /// Null if either [expectedTable] or [actualTable] are null.
  SchemaTableUniqueSetDifference uniqueSetDifference;
  List<SchemaColumnDifference> differingColumns = [];

  bool get hasDifferences =>
      differingColumns.length > 0 ||
          expectedTable?.name?.toLowerCase() != actualTable?.name?.toLowerCase() ||
          (expectedTable == null && actualTable != null) ||
          (actualTable == null && expectedTable != null) ||
          (uniqueSetDifference?.hasDifferences ?? false);

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
        .expand((diff) => diff.errorMessages)
        .toList();
    diffs.addAll(uniqueSetDifference?.errorMessages ?? []);

    return diffs;
  }

  String generateUpgradeSource({List<String> changeList}) {
    var builder = new StringBuffer();

    differingColumns
        .where((diff) => diff.expectedColumn == null && diff.actualColumn != null)
        .map((diff) => diff.actualColumn)
        .forEach((c) {
      changeList?.add("Adding column '${c.name}' to table '${actualTable.name}'");
      builder.writeln(createColumnSource(c));
    });

    differingColumns
        .where((diff) => diff.expectedColumn != null && diff.actualColumn == null)
        .map((diff) => diff.expectedColumn)
        .forEach((c) {
      changeList?.add("Deleting column '${c.name}' from table '${actualTable.name}'");
      builder.writeln(deleteColumnSource(c));
    });

    differingColumns
        .where((columnDiff) => columnDiff.expectedColumn != null && columnDiff.actualColumn != null)
        .forEach((columnDiff) {
      var lines = columnDiff.generateUpgradeSource(changeList: changeList);
      builder.writeln(lines);
    });

    if (uniqueSetDifference?.hasDifferences ?? false) {
      builder.writeln(uniqueSetDifference.generateUpgradeSource(changeList: changeList));
    }

    return builder.toString();
  }

  static String createColumnSource(SchemaColumn column) {
    var builder = new StringBuffer();

    if (column.isNullable || column.defaultValue != null) {
      builder.writeln(
          'database.addColumn("${column.table.name}", ${column.source});');
    } else {
      builder.writeln(
          'database.addColumn("${column.table.name}", ${column.source}, unencodedInitialValue: <<set>>);');
    }
    return builder.toString();
  }

  static String deleteColumnSource(SchemaColumn column) {
    return 'database.deleteColumn("${column.table.name}", "${column.name}");';
  }
}

class SchemaTableUniqueSetDifference {
  SchemaTableUniqueSetDifference(SchemaTable expectedTable, SchemaTable actualTable) {
    expectedColumnNames = expectedTable.uniqueColumnSet ?? [];
    actualColumnNames = actualTable.uniqueColumnSet ?? [];
    _tableName = actualTable.name;
  }

  String _tableName;
  List<String> expectedColumnNames;
  List<String> actualColumnNames;

  bool get hasDifferences {
    if (expectedColumnNames.length != actualColumnNames.length) {
      return true;
    }

    return !expectedColumnNames.every((s) => actualColumnNames.contains(s));
  }

  List<String> get errorMessages {
    if (expectedColumnNames.isEmpty && actualColumnNames.isNotEmpty) {
      return ["Multi-column unique constraint on table '$_tableName' "
          "should NOT exist, but is created by migration files."
      ];
    } else if (expectedColumnNames.isNotEmpty && actualColumnNames.isEmpty) {
      return ["Multi-column unique constraint on table '$_tableName' "
          "should exist, but it is NOT created by migration files."
      ];
    }

    if (hasDifferences) {
      var expectedColumns = expectedColumnNames.map((c) => "'$c'").join(", ");
      var actualColumns = actualColumnNames.map((c) => "'$c'").join(", ");

      return ["Multi-column unique constraint on table '$_tableName' "
          "is expected to be for properties $expectedColumns, but is actually $actualColumns"
      ];
    }

    return [];
  }

  String generateUpgradeSource({List<String> changeList}) {
    var setString = "null";
    if (actualColumnNames.isNotEmpty) {
      setString = "[${actualColumnNames.map((s) => '"$s"').join(",")}]";
    }

    var builder = new StringBuffer();
    builder.writeln('database.alterTable("$_tableName", (t) {');
    builder.writeln("t.uniqueColumnSet = $setString;");
    builder.writeln("});");
    return builder.toString();
  }
}