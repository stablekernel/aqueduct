import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("A single, simple model", () {
    var dataModel = new DataModel([SimpleModel]);
    var schema = new Schema.fromDataModel(dataModel);
    expect(schema.tables.length, 1);
    var t = schema.tables.first;

    expect(t.name, "_SimpleModel");
    var tableColumns = t.columns;
    expect(tableColumns.length, 1);
    expect(tableColumns.first.asMap(), {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });
  });

  test("An extensive model", () {
    var dataModel = new DataModel([ExtensiveModel]);
    var schema = new Schema.fromDataModel(dataModel);
    expect(schema.tables.length, 1);

    var table = schema.tables.first;
    expect(table.name, "_ExtensiveModel");

    var columns = table.columns;
    expect(columns.length, 8);

    expect(columns.firstWhere((c) => c.name == "id").asMap(), {
      "name" : "id",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "startDate").asMap(), {
      "name" : "startDate",
      "type" : "datetime",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "indexedValue").asMap(), {
      "name" : "indexedValue",
      "type" : "integer",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : true
    });

    expect(columns.firstWhere((c) => c.name == "autoincrementValue").asMap(), {
      "name" : "autoincrementValue",
      "type" : "integer",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "uniqueValue").asMap(), {
      "name" : "uniqueValue",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : true,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "defaultItem").asMap(), {
      "name" : "defaultItem",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : "'foo'",
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "nullableValue").asMap(), {
      "name" : "nullableValue",
      "type" : "boolean",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    expect(columns.firstWhere((c) => c.name == "loadedValue").asMap(), {
      "name" : "loadedValue",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : true,
      "unique" : true,
      "defaultValue" : "7",
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : true
    });
  });

  test("A model graph", () {
    var dataModel = new DataModel([Container, DefaultItem, LoadedItem, LoadedSingleItem]);
    var schema = new Schema.fromDataModel(dataModel);

    expect(schema.tables.length, 4);

    var containerTable = schema.tables.firstWhere((t) => t.name == "_Container");
    expect(containerTable.name, "_Container");
    var containerColumns = containerTable.columns;
    expect(containerColumns.length, 1);
    expect(containerColumns.first.asMap(), {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });

    var defaultItemTable = schema.tables.firstWhere((t) => t.name == "_DefaultItem");
    expect(defaultItemTable.name, "_DefaultItem");
    var defaultItemColumns = defaultItemTable.columns;
    expect(defaultItemColumns.length, 2);
    expect(defaultItemColumns.first.asMap(), {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });
    expect(defaultItemColumns.last.asMap(), {
      "name" : "container",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : "_Container",
      "relatedColumnName" : "id",
      "deleteRule" : "nullify",
      "indexed" : true
    });

    var loadedItemTable = schema.tables.firstWhere((t) => t.name == "_LoadedItem");
    expect(loadedItemTable.name, "_LoadedItem");
    var loadedColumns = loadedItemTable.columns;
    expect(loadedColumns.length, 3);
    expect(loadedColumns[0].asMap(), {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });
    expect(loadedColumns[1].asMap(), {
      "name" : "someIndexedThing",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : true
    });
    expect(loadedColumns[2].asMap(), {
      "name" : "container",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : "_Container",
      "relatedColumnName" : "id",
      "deleteRule" : "restrict",
      "indexed" : true
    });

    var loadedSingleItemTable = schema.tables.firstWhere((t) => t.name == "_LoadedSingleItem");
    expect(loadedSingleItemTable.name, "_LoadedSingleItem");
    var loadedSingleColumns = loadedSingleItemTable.columns;
    expect(loadedSingleColumns.length, 2);
    expect(loadedSingleColumns[0].asMap(), {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true,
      "relatedTableName" : null,
      "relatedColumnName" : null,
      "deleteRule" : null,
      "indexed" : false
    });
    expect(loadedSingleColumns[1].asMap(), {
      "name" : "container",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : true,
      "defaultValue" : null,
      "primaryKey" : false,
      "relatedTableName" : "_Container",
      "relatedColumnName" : "id",
      "deleteRule" : "cascade",
      "indexed" : true
    });
  });
}

class Container extends Model<_Container> implements _Container {}
class _Container {
  @primaryKey
  int id;

  OrderedSet<DefaultItem> defaultItems;
  OrderedSet<LoadedItem> loadedItems;
  LoadedSingleItem loadedSingleItem;
}

class DefaultItem extends Model<_DefaultItem> implements _DefaultItem {}
class _DefaultItem {
  @primaryKey
  int id;

  @RelationshipInverse(#defaultItems)
  Container container;
}

class LoadedItem extends Model<_LoadedItem> {}
class _LoadedItem {
  @primaryKey
  int id;

  @ColumnAttributes(indexed: true)
  String someIndexedThing;

  @RelationshipInverse(#loadedItems, onDelete: RelationshipDeleteRule.restrict, isRequired: false)
  Container container;
}

class LoadedSingleItem extends Model<_LoadedSingleItem> {}
class _LoadedSingleItem {
  @primaryKey
  int id;

  @RelationshipInverse(#loadedSingleItem, onDelete: RelationshipDeleteRule.cascade, isRequired: true)
  Container container;
}

class SimpleModel extends Model<_SimpleModel> implements _SimpleModel {}
class _SimpleModel {
  @primaryKey
  int id;
}

class ExtensiveModel extends Model<_ExtensiveModel> implements _ExtensiveModel {
  @transientAttribute
  String transientProperty;
}
class _ExtensiveModel {
  @ColumnAttributes(primaryKey: true, databaseType: PropertyType.string)
  String id;

  DateTime startDate;

  @ColumnAttributes(indexed: true)
  int indexedValue;

  @ColumnAttributes(autoincrement: true)
  int autoincrementValue;

  @ColumnAttributes(unique: true)
  String uniqueValue;

  @ColumnAttributes(defaultValue: "'foo'")
  String defaultItem;

  @ColumnAttributes(nullable: true)
  bool nullableValue;

  @ColumnAttributes(databaseType: PropertyType.bigInteger, nullable: true, defaultValue: "7", unique: true, indexed: true, autoincrement: true)
  int loadedValue;
}