part of aqueduct;

class SchemaTable extends SchemaElement {
  SchemaTable(this.name, this.columns);

  SchemaTable.fromEntity(ModelEntity entity) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) => (p is AttributeDescription && !p.isTransient) || (p is RelationshipDescription && p.relationshipType == RelationshipType.belongsTo))
        .toList();

    columns = validProperties
        .map((p) => new SchemaColumn.fromEntity(entity, p))
        .toList();
  }

  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    columns = otherTable.columns.map((col) => new SchemaColumn.from(col)).toList();
  }

  SchemaTable.empty();

  String name;
  List<SchemaColumn> columns;

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  bool matches(SchemaTable table) {
    if (columns.length != table.columns.length) {
      return false;
    }

    return table.columns.every((otherColumn) {
      return columnForName(otherColumn.name).matches(otherColumn);
    });
  }

  void addColumn(SchemaColumn column) {
    if (columnForName(column.name) != null) {
      throw new SchemaException("Column ${column.name} already exists.");
    }

    columns.add(column);
  }

  void renameColumn(SchemaColumn column, String newName) {
    if (!columns.contains(column)) {
      throw new SchemaException("Column ${column.name} does not exist on ${name}.");
    }

    if (columnForName(newName) != null) {
      throw new SchemaException("Column ${newName} already exists.");
    }

    if (column.isPrimaryKey) {
      throw new SchemaException("May not rename primary key column (${column.name} -> ${newName})");
    }

    // We also must rename indices
    column.name = newName;
  }

  void removeColumn(SchemaColumn column) {
    if (!columns.contains(column)) {
      throw new SchemaException("Column ${column.name} does not exist on ${name}.");
    }

    columns.remove(column);
  }

  void _replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    if (!columns.contains(existingColumn)) {
      throw new SchemaException("Column ${existingColumn.name} does not exist on ${name}.");
    }

    var index = columns.indexOf(existingColumn);
    columns[index] = newColumn;
  }

  SchemaColumn columnForName(String name) {
    var lowercaseName = name.toLowerCase();
    return columns.firstWhere((col) => col.name.toLowerCase() == lowercaseName, orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {
      "name" : name,
      "columns" : columns.map((c) => c.asMap()).toList()
    };
  }

  String toString() => name;
}