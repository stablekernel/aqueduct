import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("A single, simple model", () {
    var dataModel = new DataModel([SimpleModel]);
    var generator = new SchemaGenerator(new DefaultPersistentStore(), dataModel);
    var json = generator.serialized;
    expect(json.length, 1);
    expect(json.first["op"], "table.add");

    var tableJSON = json.first["table"];
    expect(tableJSON["name"], "_SimpleModel");
    expect(tableJSON["indexes"], []);
    expect(tableJSON["constraints"], []);

    var tableColumns = tableJSON["columns"];
    expect(tableColumns.length, 1);
    expect(tableColumns.first, {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });
  });

  test("An extensive model", () {
    var dataModel = new DataModel([ExtensiveModel]);
    var generator = new SchemaGenerator(new DefaultPersistentStore(), dataModel);
    var json = generator.serialized;
    expect(json.length, 1);
    expect(json.first["op"], "table.add");

    var tableJSON = json.first["table"];
    expect(tableJSON["name"], "_ExtensiveModel");

    var indexes = tableJSON["indexes"];
    expect(indexes.length, 2);
    expect(indexes.first["name"], "indexedValue");
    expect(indexes.last["name"], "loadedValue");

    expect(tableJSON["constraints"], []);

    var columns = tableJSON["columns"];
    expect(columns.length, 8);

    expect(columns.firstWhere((c) => c["name"] == "id"), {
      "name" : "id",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });

    expect(columns.firstWhere((c) => c["name"] == "startDate"), {
      "name" : "startDate",
      "type" : "datetime",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "indexedValue"), {
      "name" : "indexedValue",
      "type" : "integer",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "autoincrementValue"), {
      "name" : "autoincrementValue",
      "type" : "integer",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "uniqueValue"), {
      "name" : "uniqueValue",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : true,
      "defaultValue" : null,
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "defaultItem"), {
      "name" : "defaultItem",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : "'foo'",
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "nullableValue"), {
      "name" : "nullableValue",
      "type" : "boolean",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    expect(columns.firstWhere((c) => c["name"] == "loadedValue"), {
      "name" : "loadedValue",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : true,
      "unique" : true,
      "defaultValue" : "7",
      "primaryKey" : false
    });
  });

  test("A model graph", () {
    var dataModel = new DataModel([Container, DefaultItem, LoadedItem, LoadedSingleItem]);
    var generator = new SchemaGenerator(new DefaultPersistentStore(), dataModel);
    var json = generator.serialized;

    expect(json.length, 4);
    expect(json.every((i) => i["op"] == "table.add"), true);

    var containerTable = json.firstWhere((op) => op["table"]["name"] == "_Container")["table"];
    expect(containerTable["name"], "_Container");
    expect(containerTable["indexes"].length, 0);
    expect(containerTable["constraints"].length, 0);
    var containerColumns = containerTable["columns"];
    expect(containerColumns.length, 1);
    expect(containerColumns.first, {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });

    var defaultItemTable = json.firstWhere((op) => op["table"]["name"] == "_DefaultItem")["table"];
    expect(defaultItemTable["name"], "_DefaultItem");
    expect(defaultItemTable["indexes"], [
      {"name" : "container_id"}
    ]);
    expect(defaultItemTable["constraints"], [{
      "foreignTableName" : "_Container",
      "foreignColumnName" : "id",
      "deleteRule" : "nullify",
      "columnName" : "container_id"
    }]);
    var defaultItemColumns = defaultItemTable["columns"];
    expect(defaultItemColumns.length, 2);
    expect(defaultItemColumns.first, {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });
    expect(defaultItemColumns.last, {
      "name" : "container_id",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    var loadedItemTable = json.firstWhere((op) => op["table"]["name"] == "_LoadedItem")["table"];
    expect(loadedItemTable ["name"], "_LoadedItem");
    expect(loadedItemTable ["indexes"], [
      {"name" : "someIndexedThing"},
      {"name" : "container_id"}
    ]);
    expect(loadedItemTable ["constraints"], [{
      "foreignTableName" : "_Container",
      "foreignColumnName" : "id",
      "deleteRule" : "restrict",
      "columnName" : "container_id"
    }]);
    var loadedColumns = loadedItemTable["columns"];
    expect(loadedColumns.length, 3);
    expect(loadedColumns[0], {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });
    expect(loadedColumns[1], {
      "name" : "someIndexedThing",
      "type" : "string",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });
    expect(loadedColumns[2], {
      "name" : "container_id",
      "type" : "bigInteger",
      "nullable" : true,
      "autoincrement" : false,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : false
    });

    var loadedSingleItemTable = json.firstWhere((op) => op["table"]["name"] == "_LoadedSingleItem")["table"];
    expect(loadedSingleItemTable ["name"], "_LoadedSingleItem");
    expect(loadedSingleItemTable ["indexes"], [
      {"name" : "container_id"}
    ]);
    expect(loadedSingleItemTable ["constraints"], [{
      "foreignTableName" : "_Container",
      "foreignColumnName" : "id",
      "deleteRule" : "cascade",
      "columnName" : "container_id"
    }]);
    var loadedSingleColumns = loadedSingleItemTable["columns"];
    expect(loadedSingleColumns.length, 2);
    expect(loadedSingleColumns[0], {
      "name" : "id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : true,
      "unique" : false,
      "defaultValue" : null,
      "primaryKey" : true
    });
    expect(loadedSingleColumns[1], {
      "name" : "container_id",
      "type" : "bigInteger",
      "nullable" : false,
      "autoincrement" : false,
      "unique" : true,
      "defaultValue" : null,
      "primaryKey" : false
    });
  });
}

class Container extends Model<_Container> implements _Container {}
class _Container {
  @primaryKey
  int id;

  @RelationshipAttribute.hasMany("container")
  List<DefaultItem> defaultItems;

  @RelationshipAttribute.hasMany("container")
  List<LoadedItem> loadedItems;

  @RelationshipAttribute.hasOne("container")
  LoadedSingleItem loadedSingleItem;
}

class DefaultItem extends Model<_DefaultItem> implements _DefaultItem {}
class _DefaultItem {
  @primaryKey
  int id;

  @RelationshipAttribute.belongsTo("defaultItems")
  Container container;
}

class LoadedItem extends Model<_LoadedItem> {}
class _LoadedItem {
  @primaryKey
  int id;

  @Attributes(indexed: true)
  String someIndexedThing;

  @RelationshipAttribute.belongsTo("loadedItems", deleteRule: RelationshipDeleteRule.restrict, required: false)
  Container container;
}

class LoadedSingleItem extends Model<_LoadedSingleItem> {}
class _LoadedSingleItem {
  @primaryKey
  int id;

  @RelationshipAttribute.belongsTo("loadedSingleItem", deleteRule: RelationshipDeleteRule.cascade, required: true)
  Container container;
}

class SimpleModel extends Model<_SimpleModel> implements _SimpleModel {}
class _SimpleModel {
  @primaryKey
  int id;
}

class ExtensiveModel extends Model<_ExtensiveModel> implements _ExtensiveModel {}
class _ExtensiveModel {
  @Attributes(primaryKey: true, databaseType: PropertyType.string)
  String id;

  DateTime startDate;

  @Attributes(indexed: true)
  int indexedValue;

  @Attributes(autoincrement: true)
  int autoincrementValue;

  @Attributes(unique: true)
  String uniqueValue;

  @Attributes(defaultValue: "'foo'")
  String defaultItem;

  @Attributes(nullable: true)
  bool nullableValue;

  @Attributes(databaseType: PropertyType.bigInteger, nullable: true, defaultValue: "7", unique: true, indexed: true, autoincrement: true)
  int loadedValue;
}