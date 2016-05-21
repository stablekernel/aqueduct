part of aqueduct;

class PostgreSQLSchemaGenerator extends SchemaGeneratorBackend {
  PostgreSQLSchemaGenerator(List<Map> operations, {bool temporary: false}) : super(operations, temporary: temporary) {
    commands = [];
    commands.addAll(tableCommands);
    commands.addAll(indexCommands);
    commands.addAll(constraintCommands);
  }

  List<String> tableCommands = [];
  List<String> indexCommands = [];
  List<String> constraintCommands = [];


  void handleAddTableCommand(SchemaTable table) {
    List<SchemaColumn> sortedColumns = new List.from(table.columns);
    sortedColumns.sort((a, b) => a.name.compareTo(b.name));
    var columnString = sortedColumns.map((sc) => _columnStringForColumn(sc)).join(",");

    tableCommands.add("create${isTemporary ? " temporary " : " "}table ${table.name} (${columnString});");

    List<SchemaIndex> sortedIndexes = new List.from(table.indexes);
    sortedIndexes.sort((a, b) => a.name.compareTo(b.name));
    indexCommands.addAll(sortedIndexes.map((i) => _indexStringForTableIndex(table, i)).toList());

    List<SchemaForeignKeyConstraint> sortedConstraints = new List.from(table.foreignKeyConstraints);
    sortedConstraints.sort((a, b) => a.columnName.compareTo(b.columnName));
    constraintCommands.addAll(sortedConstraints.map((c) => _foreignKeyConstraintForTableConstraint(table, c)).toList());
  }

  String _foreignKeyConstraintForTableConstraint(SchemaTable sourceTable, SchemaForeignKeyConstraint constraint) =>
      "alter table only ${sourceTable.name} add foreign key (${constraint.columnName}) "
          "references ${constraint.foreignTableName} (${constraint.foreignColumnName}) "
          "on delete ${_deleteRuleStringForDeleteRule(constraint.deleteRule)};";

  String _indexStringForTableIndex(SchemaTable table, SchemaIndex i) =>
      "create index ${table.name}_${i.name}_idx on ${table.name} (${i.name});";

  String _columnStringForColumn(SchemaColumn col) {
    var elements = [col.name, _postgreSQLTypeForColumn(col)];

    if (col.isPrimaryKey) {
      elements.add("primary key");
    } else {
      elements.add(col.isNullable ? "null" : "not null");
      if (col.defaultValue != null) {
        elements.add("default ${col.defaultValue}");
      }
      if (col.isUnique) {
        elements.add("unique");
      }
    }

    return elements.join(" ");
  }

  String _deleteRuleStringForDeleteRule(String deleteRule) {
    switch (deleteRule) {
      case "cascade":
        return "cascade";
      case "restrict":
        return "restrict";
      case "default":
        return "set default";
      case "nullify":
        return "set null";
    }
  }

  String _postgreSQLTypeForColumn(SchemaColumn t) {
    switch (t.type) {
      case "integer": {
        if (t.autoincrement) {
          return "serial";
        }
        return "int";
      } break;
      case "bigInteger": {
        if (t.autoincrement) {
          return "bigserial";
        }
        return "bigint";
      } break;
      case "string":
        return "text";
      case "datetime":
        return "timestamp";
      case "boolean":
        return "boolean";
      case "double":
        return "double precision";
    }

    return null;
  }
}

//class PostgresqlSchema {
//  static Type entityTypeForModelType(Type t) {
//    return reflectClass(t).superclass.typeArguments.first.reflectedType;
//  }
//
//  PostgresqlSchema.fromModels(List<Type> modelTypes, {bool temporary: false}) {
//    tables = new Map.fromIterable(modelTypes, key: (typeKey) => typeKey, value: (t) {
//      var entity = ModelEntity.entityForType(entityTypeForModelType(t));
//      var table = new _PostgresqlTable.fromEntity(entity, temporary);
//      return table;
//    });
//
//    tables.values.forEach((table) {
//      table.updateRelationshipsWithTables(tables);
//    });
//
//    tables.values.forEach((t) {
//      t.verify(tables);
//    });
//  }
//
//  Map<Type, _PostgresqlTable> tables;
//
//  String toString() {
//    var buffer = new StringBuffer();
//    schemaDefinition().forEach((cmd) {
//      buffer.write("${cmd};\n");
//    });
//    return buffer.toString();
//  }
//
//  List<String> schemaDefinition() {
//    var tableDefinitions = tables.values.map((t) => t.tableDefinition()).toList();
//    var constraintDefinitions = tables.values.map((t) => t.constraintDefinitions()).expand((e) => e).toList();
//
//    return [tableDefinitions, constraintDefinitions].expand((e) => e).toList();
//  }
//}
//
//class _PostgresqlTable {
//  ModelEntity entity;
//  Type type;
//  bool isTemporary;
//  String name;
//
//  // Key is the modelKey (property) of the model object. A column stores the database column name.
//  Map<String, _PostgresqlColumn> columns;
//
//  _PostgresqlColumn get primaryKeyColumn => columns[entity.primaryKey];
//
//  _PostgresqlTable.fromEntity(ModelEntity t, bool temporary) {
//    entity = t;
//    this.type = entity.entityTypeMirror.reflectedType;
//    this.isTemporary = temporary;
//
//    name = entity.tableName;
//
//    columns = new Map.fromIterable(entity._propertyCache.keys,
//        key: (key) => key,
//        value: (key) => new _PostgresqlColumn.fromVariableMirror(entity._propertyCache[key], this));
//  }
//
//  void updateRelationshipsWithTables(Map<Type, _PostgresqlTable> tables) {
//    var columnsWithRelationships = columns.values.where((column) => column.relationship != null);
//
//    columnsWithRelationships.forEach((column) {
//      column.updateWithTables(tables);
//    });
//  }
//
//  String tableDefinition() {
//    var sortedColumns = new List.from(columns.values);
//    sortedColumns.sort((a, b) => a.name.compareTo(b.name));
//    var joinedColumns = sortedColumns.where((column) => !column.ignoreWhenGeneratingSQL()).join(",");
//
//    var tableDefinition = "create${isTemporary
//        ? " temporary "
//        : " "}table ${name} (${joinedColumns})";
//
//    return tableDefinition;
//  }
//
//  List<String> constraintDefinitions() {
//    var indexedColumns = columns.values.where((v) => v.isIndexed).toList();
//    var indexDefinitions =
//        indexedColumns.map((column) => "create index ${name}_${column.name}_idx on ${name} (${column.name})");
//
//    var foreignKeyColumns = columns.values.where((column) => column.relationship != null && !column.ignoreWhenGeneratingSQL());
//    var foreignKeyDefinitions = foreignKeyColumns.map((column) {
//      return "alter table only ${name} add foreign key (${column.name}) "
//          "references ${column.relationship.entity.tableName} (${column.relationship.foreignColumnName}) "
//          "on delete ${column.relationship.deleteRuleText()}";
//    });
//
//    var items = [];
//    items.addAll(indexDefinitions);
//    items.addAll(foreignKeyDefinitions);
//
//    return items;
//  }
//
//  void verify(Map<Type, _PostgresqlTable> tables) {
//    if (name == null) {
//      throw new PostgresqlGeneratorException("Table for $type has no name.");
//    }
//
//    columns.values.forEach((c) {
//      c.verify(this, tables);
//    });
//  }
//}
//
//class _PostgresqlColumn {
//  bool isPrimaryKey;
//  String sqlType;
//  bool isNullable;
//  String defaultValue;
//  bool isUnique;
//  bool isIndexed;
//  bool shouldOmitFromDefaultSet;
//  String name;
//  _PostgresqlRelationship relationship;
//
//  bool get isRealColumn {
//    if (relationship == null) {
//      return true;
//    }
//    if (relationship.type == RelationshipType.hasMany || relationship.type == RelationshipType.hasOne) {
//      return false;
//    }
//    return true;
//  }
//
//  _PostgresqlColumn.fromVariableMirror(VariableMirror mirror, _PostgresqlTable table) {
//    name = MirrorSystem.getName(mirror.simpleName);
//
//    var r = relationshipAttributesForMirror(mirror);
//    if (r != null) {
//      relationship = new _PostgresqlRelationship(mirror, r);
//    }
//
//    var attributes = adjustedAttributesFromMirror(mirror);
//    isPrimaryKey = attributes.isPrimaryKey;
//    sqlType = attributes.databaseType;
//    isNullable = attributes.isNullable;
//    defaultValue = attributes.defaultValue;
//    isUnique = attributes.isUnique;
//    isIndexed = attributes.isIndexed;
//    shouldOmitFromDefaultSet = attributes.shouldOmitByDefault;
//
//    if (relationship != null && relationship.type == RelationshipType.belongsTo) {
//      isIndexed = true;
//    }
//  }
//
//  RelationshipAttribute relationshipAttributesForMirror(VariableMirror m) {
//    var attrMirr = m.metadata.firstWhere((attr) => attr.reflectee is RelationshipAttribute, orElse: () => null);
//
//    if (attrMirr != null) {
//      return attrMirr.reflectee;
//    }
//
//    return null;
//  }
//
//  Attributes modelAttributesForMirror(VariableMirror m) {
//    var attrMirr = m.metadata.firstWhere((attr) => attr.reflectee is Attributes, orElse: () => null);
//
//    if (attrMirr != null) {
//      return attrMirr.reflectee;
//    }
//
//    return null;
//  }
//
//  Attributes adjustedAttributesFromMirror(VariableMirror mirror) {
//    var propertyType = mirror.type.reflectedType;
//
//    var columnAttrs = modelAttributesForMirror(mirror);
//    if (columnAttrs == null) {
//      // Use defaults if we haven't specified any attributes
//      return new Attributes(databaseType: _sqlTypeForDartType(propertyType));
//    } else if (columnAttrs.databaseType == null) {
//      // Use attributes, but inject default column type for variable type if not defined explicitly
//      return new Attributes.fromAttributes(columnAttrs, _sqlTypeForDartType(propertyType));
//    }
//
//    return columnAttrs;
//  }
//
//  void updateWithTables(Map<Type, _PostgresqlTable> tables) {
//    if (this.ignoreWhenGeneratingSQL()) {
//      return;
//    }
//
//    // Need to set the column type, rename the column, apply unique
//    var referenceTable = tables[relationship.destinationType];
//    if (referenceTable == null) {
//      throw new PostgresqlGeneratorException("Reference table for $name not found, has ${relationship.destinationType} been added to the schema?");
//    }
//
//    var foreignModelKey = relationship.destinationModelKey ?? referenceTable.primaryKeyColumn.name;
//    var referenceColumn = referenceTable.columns[foreignModelKey];
//    if (referenceColumn == null) {
//      throw new PostgresqlGeneratorException("Reference column for $name not found, expected ${relationship.inverseModelKey} on ${referenceTable.name}.");
//    }
//
//    this.sqlType = referenceColumn.sqlType;
//    if (this.sqlType == "bigserial" || this.sqlType == "bigserial8") {
//      this.sqlType = "bigint";
//    }
//    if (this.sqlType == "serial" || this.sqlType == "serial4") {
//      this.sqlType = "int";
//    }
//
//    this.name = "${this.name}_${referenceColumn.name}";
//    this.relationship.destinationModelKey = foreignModelKey;
//    this.relationship.foreignColumnName = referenceColumn.name;
//
//    var inverseColumn = referenceTable.columns[relationship.inverseModelKey];
//    if (inverseColumn == null || inverseColumn.relationship == null) {
//      throw new PostgresqlGeneratorException("No inverse column (or relationship) for $name, referencing table ${referenceTable.name}");
//    }
//
//    if (inverseColumn.relationship.type == RelationshipType.hasOne) {
//      this.isUnique = true;
//    }
//  }
//
//  String _sqlTypeForDartType(Type t) {
//    switch (t) {
//      case int:
//        return "int";
//      case String:
//        return "text";
//      case DateTime:
//        return "timestamp";
//      case bool:
//        return "boolean";
//      case double:
//        return "double precision";
//    }
//
//    return null;
//  }
//
//  bool ignoreWhenGeneratingSQL() {
//    if (relationship == null) {
//      return false;
//    }
//    if (relationship.type == RelationshipType.belongsTo) {
//      return false;
//    }
//
//    return true;
//  }
//
//  String toString() {
//    var elements = [];
//
//    elements.add(sqlType);
//
//    // Primary key implies nonnull
//    if (isPrimaryKey) {
//      elements.add("primary key");
//    } else {
//      if (isNullable) {
//        elements.add("null");
//      } else {
//        elements.add("not null");
//      }
//    }
//
//    if (defaultValue != null) {
//      elements.add("default ${defaultValue}");
//    }
//
//    if (isUnique) {
//      elements.add("unique");
//    }
//
//    return "${name} ${elements.join(' ')}";
//  }
//
//  void verify(_PostgresqlTable owningTable, Map<Type, _PostgresqlTable> tables) {
//    if (isRealColumn && sqlType == null) {
//      throw new PostgresqlGeneratorException("Column $name of ${owningTable
//          .name} has no type; should it be marked with @RelationshipAttribute?");
//    }
//
//    if (relationship != null) {
//      if (relationship.type == RelationshipType.belongsTo) {
//        if (relationship.deleteRule == RelationshipDeleteRule.nullify && isNullable == false) {
//          throw new PostgresqlGeneratorException("${owningTable
//                  .name} will set relationship '${name}' to null on delete, but '${name}' may not be null");
//        }
//
//        if (relationship.destinationModelKey == null || relationship.foreignColumnName == null) {
//          throw new PostgresqlGeneratorException("Relationship cannot be established from ${owningTable
//                  .name}.$name.");
//        }
//      }
//    }
//  }
//}
//
//class _PostgresqlRelationship {
//  RelationshipDeleteRule deleteRule;
//  RelationshipType type;
//  ModelEntity entity;
//  Type destinationType;
//  String destinationModelKey;
//  String inverseModelKey;
//  String foreignColumnName;
//
//  _PostgresqlRelationship(VariableMirror referenceMirror, RelationshipAttribute attribute) {
//    var variableType = referenceMirror.type;
//    if (variableType.isSubtypeOf(reflectType(List))) {
//      this.destinationType = variableType.typeArguments.first.reflectedType;
//    } else {
//      this.destinationType = variableType.reflectedType;
//    }
//
//    this.entity = ModelEntity.entityForType(this.destinationType);
//    this.destinationModelKey = attribute.referenceKey;
//    this.type = attribute.type;
//    this.deleteRule = attribute.deleteRule;
//    this.inverseModelKey = attribute.inverseKey;
//  }
//
//  String deleteRuleText() {
//    switch (deleteRule) {
//      case RelationshipDeleteRule.cascade:
//        return "cascade";
//      case RelationshipDeleteRule.restrict:
//        return "restrict";
//      case RelationshipDeleteRule.setDefault:
//        return "set default";
//      case RelationshipDeleteRule.nullify:
//        return "set null";
//    }
//    return "no action";
//  }
//}
//
//class PostgresqlGeneratorException implements Exception {
//  final String message;
//
//  const PostgresqlGeneratorException(this.message);
//
//  String toString() {
//    return "PostgresqlGeneratorException: $message";
//  }
//}