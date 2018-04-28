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
      expect(t.uniqueColumnSet, isNull);
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

      expect(new Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
    });

    test("An extensive model", () {
      var dataModel = new ManagedDataModel([ExtensiveModel]);
      var schema = new Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);

      var table = schema.tables.first;
      expect(table.name, "_ExtensiveModel");
      expect(table.uniqueColumnSet, isNull);

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

      expect(new Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
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
      expect(containerTable.uniqueColumnSet, isNull);
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
      expect(defaultItemTable.uniqueColumnSet, isNull);
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
      expect(loadedItemTable.uniqueColumnSet, isNull);
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
      expect(loadedSingleItemTable.uniqueColumnSet, isNull);
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

      expect(new Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
    });

    test("Can specify unique across multiple columns", () {
      var dataModel = new ManagedDataModel([Unique]);
      var schema = new Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);
      expect(schema.tables.first.name, "_Unique");
      expect(schema.tables.first.uniqueColumnSet, ["a", "b"]);

      var tableMap = schema.asMap()["tables"].first;
      expect(tableMap["name"], "_Unique");
      expect(tableMap["unique"], ["a", "b"]);

      var tableFromMap = new SchemaTable.fromMap(tableMap);
      expect(tableFromMap.differenceFrom(schema.tables.first).hasDifferences, false);
    });
  });

  group("Constructors work appropriately", () {
    test("Encoding/decoding is pristine", () {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.fromMap(baseSchema.asMap());
      expect(newSchema.differenceFrom(baseSchema).hasDifferences, false);
      expect(baseSchema.differenceFrom(newSchema).hasDifferences, false);
    });

    test("Copying is pristine", () {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = new Schema.fromDataModel(dataModel);
      var newSchema = new Schema.from(baseSchema);
      expect(newSchema.differenceFrom(baseSchema).hasDifferences, false);
      expect(baseSchema.differenceFrom(newSchema).hasDifferences, false);
    });
  });

  group("Matching", () {
    Schema baseSchema;
    setUp(() {
      var dataModel = new ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container, Unique]);
      baseSchema = new Schema.fromDataModel(dataModel);
    });

    test("Additional table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.addTable(new SchemaTable("foo", []));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first, contains("'foo' should NOT exist"));
    });

    test("Missing table show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.removeTable(newSchema.tables.firstWhere((t) => t.name == "_DefaultItem"));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first, contains("'_DefaultItem' should exist"));
    });

    test("Same table but renamed shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables.firstWhere((t) => t.name == "_DefaultItem").name =
          "DefaultItem";

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 2);
      expect(diff.errorMessages,
          contains(contains("'_DefaultItem' should exist")));
      expect(diff.errorMessages,
          contains(contains("'DefaultItem' should NOT exist")));
    });

    test("Table with different unique shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["a", "b", "c"];
      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages,
          contains(contains("'_Unique' is expected")));
      expect(diff.errorMessages,
          contains(contains("'a', 'b', 'c'")));

      newSchema = new Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["a", "c"];
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages,
          contains(contains("'_Unique' is expected")));
      expect(diff.errorMessages,
          contains(contains("'a', 'c'")));
    });

    test("Table with same unique, but unordered, shows as equal", () {
      expect(baseSchema.tableForName("_Unique").uniqueColumnSet, ["a", "b"]);

      var newSchema = new Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["b", "a"];

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, false);
    });

    test("Table with no unique/unique show up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = null;
      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages, contains(contains("NOT created by migration files")));
      expect(diff.errorMessages, contains(contains("Multi-column unique constraint on table '_Unique'")));

      var nextSchema = new Schema.from(newSchema);
      nextSchema.tableForName("_Unique").uniqueColumnSet = ["a", "b"];
      diff = newSchema.differenceFrom(nextSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages, contains(contains("is created by migration files")));
      expect(diff.errorMessages, contains(contains("Multi-column unique constraint on table '_Unique'")));
    });

    test("Missing column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      var t = newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem");
      var c = t.columnForName("id");
      t.removeColumn(c);

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          contains("Column 'id' in table '_DefaultItem' should exist"));
    });

    test("Additional column shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .addColumn(new SchemaColumn("foo", ManagedPropertyType.integer));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          contains("Column 'foo' in table '_DefaultItem' should NOT exist"));
    });

    test("Same column but with wrong name shows up as error", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .firstWhere((c) => c.name == "id")
          .name = "idd";

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 2);
      expect(
          diff.errorMessages,
          contains(
              contains("Column 'id' in table '_DefaultItem' should exist")));
      expect(
          diff.errorMessages,
          contains(contains(
              "Column 'idd' in table '_DefaultItem' should NOT exist")));
    });

    test("Column differences show up as errors", () {
      var newSchema = new Schema.from(baseSchema);
      var column = newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .firstWhere((c) => c.name == "id");

      column.isPrimaryKey = !column.isPrimaryKey;
      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          "Column 'id' in table '_DefaultItem' expected 'true' for 'isPrimaryKey', but migration files yield 'false'");
      column.isPrimaryKey = !column.isPrimaryKey;

      column.isIndexed = !column.isIndexed;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'false\' for \'isIndexed\', but migration files yield \'true\'');
      column.isIndexed = !column.isIndexed;

      column.isNullable = !column.isNullable;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'false\' for \'isNullable\', but migration files yield \'true\'');
      column.isNullable = !column.isNullable;

      column.autoincrement = !column.autoincrement;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'true\' for \'autoincrement\', but migration files yield \'false\'');
      column.autoincrement = !column.autoincrement;

      column.isUnique = !column.isUnique;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'false\' for \'isUnique\', but migration files yield \'true\'');
      column.isUnique = !column.isUnique;

      var captureValue = column.defaultValue;
      column.defaultValue = "foobar";
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'null\' for \'defaultValue\', but migration files yield \'foobar\'');
      column.defaultValue = captureValue;

      var capType = column.type;
      column.type = ManagedPropertyType.boolean;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'ManagedPropertyType.bigInteger\' for \'type\', but migration files yield \'ManagedPropertyType.boolean\'');
      column.type = capType;

      captureValue = column.relatedColumnName;
      column.relatedColumnName = "whatever";
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'null\' for \'relatedColumnName\', but migration files yield \'whatever\'');
      column.relatedColumnName = captureValue;

      captureValue = column.relatedTableName;
      column.relatedTableName = "whatever";
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'null\' for \'relatedTableName\', but migration files yield \'whatever\'');
      column.relatedTableName = captureValue;

      var capDeleteRule = column.deleteRule;
      column.deleteRule = DeleteRule.setDefault;
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          'Column \'id\' in table \'_DefaultItem\' expected \'null\' for \'deleteRule\', but migration files yield \'DeleteRule.setDefault\'');
      column.deleteRule = capDeleteRule;
    });

    test("Multiple reasons all show up", () {
      var newSchema = new Schema.from(baseSchema);
      newSchema.addTable(new SchemaTable("foo", []));
      var df = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem");
      df.addColumn(new SchemaColumn("foobar", ManagedPropertyType.integer));
      df.columns.firstWhere((sc) => sc.name == "id").isPrimaryKey = false;

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 3);
      expect(
          diff.errorMessages,
          contains(
              'Column \'id\' in table \'_DefaultItem\' expected \'true\' for \'isPrimaryKey\', but migration files yield \'false\''));
      expect(
          diff.errorMessages,
          contains(
              'Column \'foobar\' in table \'_DefaultItem\' should NOT exist, but is created by migration files'));
      expect(
          diff.errorMessages,
          contains(
              'Table \'foo\' should NOT exist, but is created by migration files.'));
    });

    test("Tables and columns are case-insensitive", () {
      var lowercaseSchema = new Schema([
        new SchemaTable("table",
            [new SchemaColumn("column", ManagedPropertyType.bigInteger)])
      ]);

      var uppercaseSchema = new Schema([
        new SchemaTable("TABLE",
            [new SchemaColumn("COLUMN", ManagedPropertyType.bigInteger)])
      ]);

      expect(lowercaseSchema.differenceFrom(uppercaseSchema).hasDifferences,
          false);
    });

    test("A model with an overridden property from a partial", () {
      var dataModel = new ManagedDataModel([OverriddenModel]);
      var schema = new Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);
      var t = schema.tables.first;

      expect(t.name, "_OverriddenModel");
      var tableColumns = t.columns;
      expect(tableColumns.length, 2);
      expect(tableColumns.firstWhere((sc) => sc.name == "id").asMap(), {
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
      expect(tableColumns.firstWhere((sc) => sc.name == "field").asMap(), {
        "name": "field",
        "type": "string",
        "nullable": false,
        "autoincrement": false,
        "unique": true,
        "defaultValue": null,
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": true
      });
    });
  });
}

class Container extends ManagedObject<_Container> implements _Container {}

class _Container {
  @primaryKey
  int id;

  ManagedSet<DefaultItem> defaultItems;
  ManagedSet<LoadedItem> loadedItems;
}

class DefaultItem extends ManagedObject<_DefaultItem> implements _DefaultItem {}

class _DefaultItem {
  @primaryKey
  int id;

  @Relate(#defaultItems)
  Container container;
}

class LoadedItem extends ManagedObject<_LoadedItem> {}

class _LoadedItem {
  @primaryKey
  int id;

  @Column(indexed: true)
  String someIndexedThing;

  @Relate(#loadedItems,
      onDelete: DeleteRule.restrict, isRequired: false)
  Container container;

  LoadedSingleItem loadedSingleItem;
}

class LoadedSingleItem extends ManagedObject<_LoadedSingleItem> {}

class _LoadedSingleItem {
  @primaryKey
  int id;

  @Relate(#loadedSingleItem,
      onDelete: DeleteRule.cascade, isRequired: true)
  LoadedItem loadedItem;
}

class SimpleModel extends ManagedObject<_SimpleModel> implements _SimpleModel {}

class _SimpleModel {
  @primaryKey
  int id;
}

class ExtensiveModel extends ManagedObject<_ExtensiveModel>
    implements _ExtensiveModel {
  @Serialize()
  String transientProperty;
}

class _ExtensiveModel {
  @Column(
      primaryKey: true, databaseType: ManagedPropertyType.string)
  String id;

  DateTime startDate;

  @Column(indexed: true)
  int indexedValue;

  @Column(autoincrement: true)
  int autoincrementValue;

  @Column(unique: true)
  String uniqueValue;

  @Column(defaultValue: "'foo'")
  String defaultItem;

  @Column(nullable: true)
  bool nullableValue;

  @Column(
      databaseType: ManagedPropertyType.bigInteger,
      nullable: true,
      defaultValue: "7",
      unique: true,
      indexed: true,
      autoincrement: true)
  int loadedValue;
}

class OverriddenModel extends ManagedObject<_OverriddenModel> implements _OverriddenModel {}
class _OverriddenModel extends PartialModel {
  @override
  @Column(indexed: true, unique: true)
  @Validate.oneOf(const ["a", "b"])
  String field;
}

class PartialModel {
  @primaryKey
  int id;

  @Column(indexed: true)
  String field;
}

class Unique extends ManagedObject<_Unique> implements _Unique {}
@Table.unique(const [#a, #b])
class _Unique {
  @primaryKey
  int id;

  String a;
  String b;
  String c;
}