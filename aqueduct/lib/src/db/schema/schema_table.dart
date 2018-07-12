import 'schema.dart';
import '../managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

/// A portable representation of a database table.
///
/// Instances of this type contain the database-only details of a [ManagedEntity]. See also [Schema].
class SchemaTable {
  /// Creates an instance of this type with a [name], [columns] and [uniqueColumnSetNames].
  SchemaTable(this.name, List<SchemaColumn> columns, {List<String> uniqueColumnSetNames}) {
    this.uniqueColumnSet = uniqueColumnSetNames;
    _columns = columns;
  }

  /// Creates an instance of this type to mirror [entity].
  SchemaTable.fromEntity(ManagedEntity entity) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) =>
            (p is ManagedAttributeDescription && !p.isTransient) ||
            (p is ManagedRelationshipDescription && p.relationshipType == ManagedRelationshipType.belongsTo))
        .toList();

    _columns = validProperties.map((p) => new SchemaColumn.fromProperty(p)).toList();

    uniqueColumnSet = entity.uniquePropertySet?.map((p) => p.name)?.toList();
  }

  /// Creates a deep copy of [otherTable].
  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    _columns = otherTable.columns.map((col) => new SchemaColumn.from(col)).toList();
    _uniqueColumnSet = otherTable._uniqueColumnSet;
  }

  /// Creates an empty table.
  SchemaTable.empty();

  /// Creates an instance of this type from [map].
  ///
  /// This [map] is typically generated from [asMap];
  SchemaTable.fromMap(Map<String, dynamic> map) {
    name = map["name"] as String;
    _columns = (map["columns"] as List<Map<String, dynamic>>).map((c) => new SchemaColumn.fromMap(c)).toList();
    uniqueColumnSet = (map["unique"] as List)?.cast();
  }

  /// The [Schema] this table belongs to.
  ///
  /// May be null if not assigned to a [Schema].
  Schema schema;

  /// The name of the database table.
  String name;

  /// The names of a set of columns that must be unique for each row in this table.
  ///
  /// Are sorted alphabetically. Not modifiable.
  List<String> get uniqueColumnSet => _uniqueColumnSet != null ? new List.unmodifiable(_uniqueColumnSet) : null;

  set uniqueColumnSet(List<String> columnNames) {
    if (columnNames != null) {
      _uniqueColumnSet = new List.from(columnNames);
      _uniqueColumnSet?.sort((String a, String b) => a.compareTo(b));
    } else {
      _uniqueColumnSet = null;
    }
  }

  /// An unmodifiable list of [SchemaColumn]s in this table.
  List<SchemaColumn> get columns => new List.unmodifiable(_columnStorage ?? []);

  List<SchemaColumn> _columnStorage;
  List<String> _uniqueColumnSet;

  set _columns(List<SchemaColumn> columns) {
    _columnStorage = columns;
    _columnStorage.forEach((c) => c.table = this);
  }

  /// Returns a [SchemaColumn] in this instance by its name.
  ///
  /// See [columnForName] for more details.
  SchemaColumn operator [](String columnName) => columnForName(columnName);

  /// The differences between two tables.
  SchemaTableDifference differenceFrom(SchemaTable table) {
    return new SchemaTableDifference(this, table);
  }

  /// Adds [column] to this table.
  ///
  /// Sets [column]'s [SchemaColumn.table] to this instance.
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

  /// Removes [column] from this table.
  ///
  /// Sets [column]'s [SchemaColumn.table] to null.
  void removeColumn(SchemaColumn column) {
    column = this[column.name];
    if (column == null) {
      throw new SchemaException("Column ${column.name} does not exist on $name.");
    }

    _columnStorage.remove(column);
    column.table = null;
  }

  /// Replaces [existingColumn] with [newColumn] in this table.
  void replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    existingColumn = this[existingColumn.name];
    if (existingColumn == null) {
      throw new SchemaException("Column ${existingColumn.name} does not exist on $name.");
    }

    var index = _columnStorage.indexOf(existingColumn);
    _columnStorage[index] = newColumn;
    newColumn.table = this;
    existingColumn.table = null;
  }

  /// Returns a [SchemaColumn] with [name].
  ///
  /// Case-insensitively compares names of [columns] with [name]. Returns null if no column exists
  /// with [name].
  SchemaColumn columnForName(String name) {
    var lowercaseName = name.toLowerCase();
    return columns.firstWhere((col) => col.name.toLowerCase() == lowercaseName, orElse: () => null);
  }

  /// Returns portable representation of this table.
  Map<String, dynamic> asMap() {
    return {"name": name, "columns": columns.map((c) => c.asMap()).toList(), "unique": uniqueColumnSet};
  }

  @override
  String toString() => name;
}

/// The difference between two [SchemaTable]s.
///
/// This class is used for comparing schemas for validation and migration.
class SchemaTableDifference {
  /// Creates a new instance that represents the difference between [expectedTable] and [actualTable].
  SchemaTableDifference(this.expectedTable, this.actualTable) {
    if (expectedTable != null && actualTable != null) {
      for (var expectedColumn in expectedTable.columns) {
        var actualColumn = (actualTable != null ? actualTable[expectedColumn.name] : null);
        if (actualColumn == null) {
          _differingColumns.add(new SchemaColumnDifference(expectedColumn, null));
        } else {
          var diff = expectedColumn.differenceFrom(actualColumn);
          if (diff.hasDifferences) {
            _differingColumns.add(diff);
          }
        }
      }

      _differingColumns.addAll(actualTable.columns.where((t) => expectedTable[t.name] == null).map((unexpectedColumn) {
        return new SchemaColumnDifference(null, unexpectedColumn);
      }));

      uniqueSetDifference = new SchemaTableUniqueSetDifference(expectedTable, actualTable);
    }
  }

  /// The expected table.
  ///
  /// May be null if no table is expected.
  final SchemaTable expectedTable;

  /// The actual table.
  ///
  /// May be null if there is no table.
  final SchemaTable actualTable;

  /// The difference between [SchemaTable.uniqueColumnSet]s.
  ///
  /// Null if either [expectedTable] or [actualTable] are null.
  SchemaTableUniqueSetDifference uniqueSetDifference;

  /// Whether or not [expectedTable] and [actualTable] are the same.
  bool get hasDifferences =>
      _differingColumns.length > 0 ||
      expectedTable?.name?.toLowerCase() != actualTable?.name?.toLowerCase() ||
      (expectedTable == null && actualTable != null) ||
      (actualTable == null && expectedTable != null) ||
      (uniqueSetDifference?.hasDifferences ?? false);

  /// Human-readable list of differences between [expectedTable] and [actualTable].
  List<String> get errorMessages {
    if (expectedTable == null && actualTable != null) {
      return ["Table '$actualTable' should NOT exist, but is created by migration files."];
    } else if (expectedTable != null && actualTable == null) {
      return ["Table '$expectedTable' should exist, but it is NOT created by migration files."];
    }

    var diffs = _differingColumns.expand((diff) => diff.errorMessages).toList();
    diffs.addAll(uniqueSetDifference?.errorMessages ?? []);

    return diffs;
  }

  List<SchemaColumnDifference> _differingColumns = [];

  /// Returns Dart code to upgrade [expectedTable] to [actualTable].
  String generateUpgradeSource({List<String> changeList}) {
    var builder = new StringBuffer();

    _differingColumns
        .where((diff) => diff.expectedColumn == null && diff.actualColumn != null)
        .map((diff) => diff.actualColumn)
        .forEach((c) {
      changeList?.add("Adding column '${c.name}' to table '${actualTable.name}'");
      builder.writeln(createColumnSource(c));
    });

    _differingColumns
        .where((diff) => diff.expectedColumn != null && diff.actualColumn == null)
        .map((diff) => diff.expectedColumn)
        .forEach((c) {
      changeList?.add("Deleting column '${c.name}' from table '${actualTable.name}'");
      builder.writeln(deleteColumnSource(c));
    });

    _differingColumns
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
      builder.writeln('database.addColumn("${column.table.name}", ${column.source});');
    } else {
      builder.writeln('database.addColumn("${column.table.name}", ${column.source}, unencodedInitialValue: <<set>>);');
    }
    return builder.toString();
  }

  static String deleteColumnSource(SchemaColumn column) {
    return 'database.deleteColumn("${column.table.name}", "${column.name}");';
  }
}

/// Difference between two [SchemaTable.uniqueColumnSet]s.
class SchemaTableUniqueSetDifference {
  SchemaTableUniqueSetDifference(SchemaTable expectedTable, SchemaTable actualTable)
      : expectedColumnNames = expectedTable.uniqueColumnSet ?? [],
        actualColumnNames = actualTable.uniqueColumnSet ?? [],
        _tableName = actualTable.name;

  /// The expected set of unique column names.
  final List<String> expectedColumnNames;

  /// The actual set of unique column names.
  final List<String> actualColumnNames;

  final String _tableName;

  /// Whether or not [expectedColumnNames] and [actualColumnNames] are equivalent.
  bool get hasDifferences {
    if (expectedColumnNames.length != actualColumnNames.length) {
      return true;
    }

    return !expectedColumnNames.every((s) => actualColumnNames.contains(s));
  }

  /// Human-readable list of differences between [expectedColumnNames] and [actualColumnNames].
  List<String> get errorMessages {
    if (expectedColumnNames.isEmpty && actualColumnNames.isNotEmpty) {
      return [
        "Multi-column unique constraint on table '$_tableName' "
            "should NOT exist, but is created by migration files."
      ];
    } else if (expectedColumnNames.isNotEmpty && actualColumnNames.isEmpty) {
      return [
        "Multi-column unique constraint on table '$_tableName' "
            "should exist, but it is NOT created by migration files."
      ];
    }

    if (hasDifferences) {
      var expectedColumns = expectedColumnNames.map((c) => "'$c'").join(", ");
      var actualColumns = actualColumnNames.map((c) => "'$c'").join(", ");

      return [
        "Multi-column unique constraint on table '$_tableName' "
            "is expected to be for properties $expectedColumns, but is actually $actualColumns"
      ];
    }

    return [];
  }

  /// Dart code to upgrade [expectedColumnNames] to [actualColumnNames].
  String generateUpgradeSource({List<String> changeList}) {
    var setString = "null";
    if (actualColumnNames.isNotEmpty) {
      setString = "[${actualColumnNames.map((s) => '"$s"').join(",")}]";
    }

    changeList?.add("Setting unique column constraint of '$_tableName' to $setString.");

    return """
database.alterTable("$_tableName", (t) {
  t.uniqueColumnSet = $setString;
});      
    """;
  }
}
