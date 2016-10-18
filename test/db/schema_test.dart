import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Generation", () {
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
      var intentionallyUnorderedModelTypes = [LoadedSingleItem, DefaultItem, LoadedItem, Container];
      var dataModel = new DataModel(intentionallyUnorderedModelTypes);
      var schema = new Schema.fromDataModel(dataModel);

      expect(schema.tables.length, 4);
      expect(schema.dependencyOrderedTables.map((t) => t.name).toList(), [
        "_Container", "_DefaultItem", "_LoadedItem", "_LoadedSingleItem"
      ]);

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
        "name" : "loadedItem",
        "type" : "bigInteger",
        "nullable" : false,
        "autoincrement" : false,
        "unique" : true,
        "defaultValue" : null,
        "primaryKey" : false,
        "relatedTableName" : "_LoadedItem",
        "relatedColumnName" : "id",
        "deleteRule" : "cascade",
        "indexed" : true
      });
    });
  });

  group("Constructors work appropriately", () {
    test("Encoding/decoding is pristine", () {
      var dataModel = new DataModel([LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.fromMap(baseSchema.asMap());
      expect(newSchema.matches(baseSchema), true);
      expect(baseSchema.matches(newSchema), true);
    });

    test("Copying is pristine", () {
      var dataModel = new DataModel([LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.from(baseSchema);
      expect(newSchema.matches(baseSchema), true);
      expect(baseSchema.matches(newSchema), true);
    });
  });

  group("Matching", () {
    Schema baseSchema;
    setUp(() {
      var dataModel = new DataModel([LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      baseSchema = new Schema.fromDataModel(dataModel);
    });

    test("Additional table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.add(new SchemaTable("foo", []));

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain foo"));
    });

    test("Missing table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.removeWhere((t) => t.name == "_DefaultItem");

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain _DefaultItem"));
    });

    test("Same table but renamed shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").name = "DefaultItem";

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain DefaultItem"));
    });

    test("Missing column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").columns.removeWhere((c) => c.name == "id");

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem does not contain id"));
    });

    test("Additional column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").columns.add(new SchemaColumn("foo", PropertyType.integer));

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem does not contain foo"));
    });

    test("Same column but with wrong name shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").columns.firstWhere((c) => c.name == "id").name = "idd";

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem does not contain id"));
    });

    test("Column differences show up as errors", () {
      var newSchema = new Schema.from(baseSchema);
      var column = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").columns.firstWhere((c) => c.name == "id");
      var errors = <String>[];

      column.isPrimaryKey = !column.isPrimaryKey;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same isPrimaryKey"));
      column.isPrimaryKey = !column.isPrimaryKey;
      errors = <String>[];

      column.isIndexed = !column.isIndexed;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same isIndexed"));
      column.isIndexed = !column.isIndexed;
      errors = <String>[];

      column.isNullable = !column.isNullable;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same isNullable"));
      column.isNullable = !column.isNullable;
      errors = <String>[];

      column.autoincrement = !column.autoincrement;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same autoincrement"));
      column.autoincrement = !column.autoincrement;
      errors = <String>[];

      column.isUnique = !column.isUnique;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same isUnique"));
      column.isUnique = !column.isUnique;
      errors = <String>[];

      var captureValue = column.defaultValue;
      column.defaultValue = "foobar";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same defaultValue"));
      column.defaultValue = captureValue;
      errors = <String>[];

      var capType = column.type;
      column.type = PropertyType.boolean;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same type"));
      column.type = capType;
      errors = <String>[];

      captureValue = column.relatedColumnName;
      column.relatedColumnName = "whatever";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same relatedColumnName"));
      column.relatedColumnName = captureValue;
      errors = <String>[];

      captureValue = column.relatedTableName;
      column.relatedTableName = "whatever";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same relatedTableName"));
      column.relatedTableName = captureValue;
      errors = <String>[];

      var capDeleteRule = column.deleteRule;
      column.deleteRule = RelationshipDeleteRule.setDefault;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("_DefaultItem.id does not have same deleteRule"));
      column.deleteRule = capDeleteRule;
      errors = <String>[];
    });

    test("Multiple reasons all show up", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.add(new SchemaTable("foo", []));
      var df = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem");
      df.columns.add(new SchemaColumn("foobar", PropertyType.integer));
      df.columns.firstWhere((sc) => sc.name == "id").isPrimaryKey = false;

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 3);
      expect(errors, contains(contains("does not contain foo")));
      expect(errors, contains(contains("_DefaultItem does not contain foobar")));
      expect(errors, contains(contains("_DefaultItem.id does not have same isPrimaryKey")));
    });
  });
}

class Container extends Model<_Container> implements _Container {}
class _Container {
  @primaryKey
  int id;

  OrderedSet<DefaultItem> defaultItems;
  OrderedSet<LoadedItem> loadedItems;
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

  LoadedSingleItem loadedSingleItem;
}

class LoadedSingleItem extends Model<_LoadedSingleItem> {}
class _LoadedSingleItem {
  @primaryKey
  int id;

  @RelationshipInverse(#loadedSingleItem, onDelete: RelationshipDeleteRule.cascade, isRequired: true)
  LoadedItem loadedItem;
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