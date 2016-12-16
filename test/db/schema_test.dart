import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Generation", () {
    test("A single, simple model", () {
      var dataModel = new ManagedDataModel([SimpleModel]);
      var schema = new Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);
      var t = schema.tables.first;

      expect(t.name, "_SimpleModel");
      var tableColumns = t.columns;
      expect(tableColumns.length, 1);
      expect(tableColumns.first.asMap(), {
        "name": "id",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });
    });

    test("An extensive model", () {
      var dataModel = new ManagedDataModel([ExtensiveModel]);
      var schema = new Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);

      var table = schema.tables.first;
      expect(table.name, "_ExtensiveModel");

      var columns = table.columns;
      expect(columns.length, 8);

      expect(columns.firstWhere((c) => c.name == "id").asMap(), {
        "name": "id",
        "type": "string",
        "nullable": false,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "startDate").asMap(), {
        "name": "startDate",
        "type": "datetime",
        "nullable": false,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "indexedValue").asMap(), {
        "name": "indexedValue",
        "type": "integer",
        "nullable": false,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": true
      });

      expect(
          columns.firstWhere((c) => c.name == "autoincrementValue").asMap(), {
        "name": "autoincrementValue",
        "type": "integer",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "uniqueValue").asMap(), {
        "name": "uniqueValue",
        "type": "string",
        "nullable": false,
        "autoincrement": false,
        "unique": true,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "defaultItem").asMap(), {
        "name": "defaultItem",
        "type": "string",
        "nullable": false,
        "autoincrement": false,
        "unique": false,
        "defaultValue": "'foo'",
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "nullableValue").asMap(), {
        "name": "nullableValue",
        "type": "boolean",
        "nullable": true,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      expect(columns.firstWhere((c) => c.name == "loadedValue").asMap(), {
        "name": "loadedValue",
        "type": "bigInteger",
        "nullable": true,
        "autoincrement": true,
        "unique": true,
        "defaultValue": "7",
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": true
      });
    });

    test("A model graph", () {
      var intentionallyUnorderedModelTypes = [
        LoadedSingleItem,
        DefaultItem,
        LoadedItem,
        Container
      ];
      var dataModel = new ManagedDataModel(intentionallyUnorderedModelTypes);
      var schema = new Schema.fromDataModel(dataModel);

      expect(schema.tables.length, 4);
      expect(schema.dependencyOrderedTables.map((t) => t.name).toList(),
          ["_Container", "_DefaultItem", "_LoadedItem", "_LoadedSingleItem"]);

      var containerTable =
          schema.tables.firstWhere((t) => t.name == "_Container");
      expect(containerTable.name, "_Container");
      var containerColumns = containerTable.columns;
      expect(containerColumns.length, 1);
      expect(containerColumns.first.asMap(), {
        "name": "id",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });

      var defaultItemTable =
          schema.tables.firstWhere((t) => t.name == "_DefaultItem");
      expect(defaultItemTable.name, "_DefaultItem");
      var defaultItemColumns = defaultItemTable.columns;
      expect(defaultItemColumns.length, 2);
      expect(defaultItemColumns.first.asMap(), {
        "name": "id",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });
      expect(defaultItemColumns.last.asMap(), {
        "name": "container",
        "type": "bigInteger",
        "nullable": true,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": "_Container",
        "relatedColumnName": "id",
        "deleteRule": "nullify",
        "indexed": true
      });

      var loadedItemTable =
          schema.tables.firstWhere((t) => t.name == "_LoadedItem");
      expect(loadedItemTable.name, "_LoadedItem");
      var loadedColumns = loadedItemTable.columns;
      expect(loadedColumns.length, 3);
      expect(loadedColumns[0].asMap(), {
        "name": "id",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });
      expect(loadedColumns[1].asMap(), {
        "name": "someIndexedThing",
        "type": "string",
        "nullable": false,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": true
      });
      expect(loadedColumns[2].asMap(), {
        "name": "container",
        "type": "bigInteger",
        "nullable": true,
        "autoincrement": false,
        "unique": false,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": "_Container",
        "relatedColumnName": "id",
        "deleteRule": "restrict",
        "indexed": true
      });

      var loadedSingleItemTable =
          schema.tables.firstWhere((t) => t.name == "_LoadedSingleItem");
      expect(loadedSingleItemTable.name, "_LoadedSingleItem");
      var loadedSingleColumns = loadedSingleItemTable.columns;
      expect(loadedSingleColumns.length, 2);
      expect(loadedSingleColumns[0].asMap(), {
        "name": "id",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": true,
        "unique": false,
        "defaultValue": null,
        "primaryKey": true,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": false
      });
      expect(loadedSingleColumns[1].asMap(), {
        "name": "loadedItem",
        "type": "bigInteger",
        "nullable": false,
        "autoincrement": false,
        "unique": true,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": "_LoadedItem",
        "relatedColumnName": "id",
        "deleteRule": "cascade",
        "indexed": true
      });
    });
  });

  group("Constructors work appropriately", () {
    test("Encoding/decoding is pristine", () {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.fromMap(baseSchema.asMap());
      expect(newSchema.matches(baseSchema), true);
      expect(baseSchema.matches(newSchema), true);
    });

    test("Copying is pristine", () {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.from(baseSchema);
      expect(newSchema.matches(baseSchema), true);
      expect(baseSchema.matches(newSchema), true);
    });
  });

  group("Matching", () {
    Schema baseSchema;
    setUp(() {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      baseSchema = new Schema.fromDataModel(dataModel);
    });

    test("Additional table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.add(new SchemaTable("foo", []));

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain 'foo'"));
    });

    test("Missing table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.removeWhere((t) => t.name == "_DefaultItem");

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain '_DefaultItem'"));
    });

    test("Same table but renamed shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").name =
          "DefaultItem";

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("does not contain 'DefaultItem'"));
    });

    test("Missing column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .removeWhere((c) => c.name == "id");

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("'_DefaultItem' does not contain 'id'"));
    });

    test("Additional column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .add(new SchemaColumn("foo", ManagedPropertyType.integer));

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("'_DefaultItem' does not contain 'foo'"));
    });

    test("Same column but with wrong name shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .firstWhere((c) => c.name == "id")
          .name = "idd";

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("'_DefaultItem' does not contain 'idd'"));
    });

    test("Column differences show up as errors", () {
      var newSchema = new Schema.from(baseSchema);
      var column = newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .firstWhere((c) => c.name == "id");
      var errors = <String>[];

      column.isPrimaryKey = !column.isPrimaryKey;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'isPrimaryKey'"));
      column.isPrimaryKey = !column.isPrimaryKey;
      errors = <String>[];

      column.isIndexed = !column.isIndexed;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'isIndexed'"));
      column.isIndexed = !column.isIndexed;
      errors = <String>[];

      column.isNullable = !column.isNullable;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'isNullable'"));
      column.isNullable = !column.isNullable;
      errors = <String>[];

      column.autoincrement = !column.autoincrement;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'autoincrement'"));
      column.autoincrement = !column.autoincrement;
      errors = <String>[];

      column.isUnique = !column.isUnique;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'isUnique'"));
      column.isUnique = !column.isUnique;
      errors = <String>[];

      var captureValue = column.defaultValue;
      column.defaultValue = "foobar";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'defaultValue'"));
      column.defaultValue = captureValue;
      errors = <String>[];

      var capType = column.type;
      column.type = ManagedPropertyType.boolean;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first, contains("'_DefaultItem.id' does not have same value for 'type'"));
      column.type = capType;
      errors = <String>[];

      captureValue = column.relatedColumnName;
      column.relatedColumnName = "whatever";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'relatedColumnName'"));
      column.relatedColumnName = captureValue;
      errors = <String>[];

      captureValue = column.relatedTableName;
      column.relatedTableName = "whatever";
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'relatedTableName'"));
      column.relatedTableName = captureValue;
      errors = <String>[];

      var capDeleteRule = column.deleteRule;
      column.deleteRule = ManagedRelationshipDeleteRule.setDefault;
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 1);
      expect(errors.first,
          contains("'_DefaultItem.id' does not have same value for 'deleteRule'"));
      column.deleteRule = capDeleteRule;
      errors = <String>[];
    });

    test("Multiple reasons all show up", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.add(new SchemaTable("foo", []));
      var df = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem");
      df.columns.add(new SchemaColumn("foobar", ManagedPropertyType.integer));
      df.columns.firstWhere((sc) => sc.name == "id").isPrimaryKey = false;

      var errors = <String>[];
      expect(newSchema.matches(baseSchema, errors), false);
      expect(errors.length, 3);
      expect(errors, contains(contains("does not contain 'foo'")));
      expect(
          errors, contains(contains("'_DefaultItem' does not contain 'foobar'")));
      expect(
          errors,
          contains(
              contains("'_DefaultItem.id' does not have same value for 'isPrimaryKey'")));
    });

    test("Tables and columns are case-insensitive", () {
      var lowercaseSchema = new Schema([
        new SchemaTable("table", [
          new SchemaColumn("column", ManagedPropertyType.bigInteger)
        ])
      ]);

      var uppercaseSchema = new Schema([
        new SchemaTable("TABLE", [
          new SchemaColumn("COLUMN", ManagedPropertyType.bigInteger)
        ])
      ]);

      expect(lowercaseSchema.matches(uppercaseSchema), true);
    });
  });
}

class Container extends ManagedObject<_Container> implements _Container {}

class _Container {
  @managedPrimaryKey
  int id;

  ManagedSet<DefaultItem> defaultItems;
  ManagedSet<LoadedItem> loadedItems;
}

class DefaultItem extends ManagedObject<_DefaultItem> implements _DefaultItem {}

class _DefaultItem {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#defaultItems)
  Container container;
}

class LoadedItem extends ManagedObject<_LoadedItem> {}

class _LoadedItem {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String someIndexedThing;

  @ManagedRelationship(#loadedItems,
      onDelete: ManagedRelationshipDeleteRule.restrict, isRequired: false)
  Container container;

  LoadedSingleItem loadedSingleItem;
}

class LoadedSingleItem extends ManagedObject<_LoadedSingleItem> {}

class _LoadedSingleItem {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#loadedSingleItem,
      onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  LoadedItem loadedItem;
}

class SimpleModel extends ManagedObject<_SimpleModel> implements _SimpleModel {}

class _SimpleModel {
  @managedPrimaryKey
  int id;
}

class ExtensiveModel extends ManagedObject<_ExtensiveModel>
    implements _ExtensiveModel {
  @managedTransientAttribute
  String transientProperty;
}

class _ExtensiveModel {
  @ManagedColumnAttributes(
      primaryKey: true, databaseType: ManagedPropertyType.string)
  String id;

  DateTime startDate;

  @ManagedColumnAttributes(indexed: true)
  int indexedValue;

  @ManagedColumnAttributes(autoincrement: true)
  int autoincrementValue;

  @ManagedColumnAttributes(unique: true)
  String uniqueValue;

  @ManagedColumnAttributes(defaultValue: "'foo'")
  String defaultItem;

  @ManagedColumnAttributes(nullable: true)
  bool nullableValue;

  @ManagedColumnAttributes(
      databaseType: ManagedPropertyType.bigInteger,
      nullable: true,
      defaultValue: "7",
      unique: true,
      indexed: true,
      autoincrement: true)
  int loadedValue;
}
