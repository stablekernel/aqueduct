import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Generation", () {
    test("A single, simple model", () {
      var dataModel = ManagedDataModel([SimpleModel]);
      var schema = Schema.fromDataModel(dataModel);
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

      expect(
          Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
    });

    test("An extensive model", () {
      var dataModel = ManagedDataModel([ExtensiveModel]);
      var schema = Schema.fromDataModel(dataModel);
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
        "autoincrement": false,
        "unique": true,
        "defaultValue": "7",
        "primaryKey": false,
        "relatedTableName": null,
        "relatedColumnName": null,
        "deleteRule": null,
        "indexed": true
      });

      expect(
          Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
    });

    test("A model graph", () {
      var intentionallyUnorderedModelTypes = [
        LoadedSingleItem,
        DefaultItem,
        LoadedItem,
        Container
      ];
      var dataModel = ManagedDataModel(intentionallyUnorderedModelTypes);
      var schema = Schema.fromDataModel(dataModel);

      expect(schema.tables.length, 4);
      expect(
          schema.tables.map((t) => t.name).toList()
            ..sort((s1, s2) => s1.compareTo(s2)),
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

      expect(
          Schema.fromMap(schema.asMap()).differenceFrom(schema).hasDifferences,
          false);
    });

    test("Can specify unique across multiple columns", () {
      var dataModel = ManagedDataModel([Unique]);
      var schema = Schema.fromDataModel(dataModel);
      expect(schema.tables.length, 1);
      expect(schema.tables.first.name, "_Unique");
      expect(schema.tables.first.uniqueColumnSet, ["a", "b"]);

      var tableMap = schema.asMap()["tables"].first as Map<String, dynamic>;
      expect(tableMap["name"], "_Unique");
      expect(tableMap["unique"], ["a", "b"]);

      var tableFromMap = SchemaTable.fromMap(tableMap);
      expect(tableFromMap.differenceFrom(schema.tables.first).hasDifferences,
          false);
    });
  });

  group("Cyclic references", () {
    test("Self-referencing table can be emitted as map", () {
      var dataModel = ManagedDataModel([SelfRef]);
      var schema = Schema.fromDataModel(dataModel);
      final map = schema.asMap();
      expect(map["tables"].first["columns"].last, {
        'name': 'parent',
        'type': 'bigInteger',
        'nullable': true,
        'autoincrement': false,
        'unique': false,
        'defaultValue': null,
        'primaryKey': false,
        'relatedTableName': '_SelfRef',
        'relatedColumnName': 'id',
        'deleteRule': 'nullify',
        'indexed': true
      });
    });

    test("Two tables related to one another can be emitted in asMap", () {
      var dataModel = ManagedDataModel([Left, Right]);
      var schema = Schema.fromDataModel(dataModel);
      final map = schema.asMap();
      expect(
          map["tables"]
              .firstWhere((t) => t["name"] == "_Left")["columns"]
              .firstWhere((c) => c["name"] == "belongsToRight"),
          {
            'name': 'belongsToRight',
            'type': 'bigInteger',
            'nullable': true,
            'autoincrement': false,
            'unique': true,
            'defaultValue': null,
            'primaryKey': false,
            'relatedTableName': '_Right',
            'relatedColumnName': 'id',
            'deleteRule': 'nullify',
            'indexed': true
          });

      expect(
          map["tables"]
              .firstWhere((t) => t["name"] == "_Right")["columns"]
              .firstWhere((c) => c["name"] == "belongsToLeft"),
          {
            'name': 'belongsToLeft',
            'type': 'bigInteger',
            'nullable': true,
            'autoincrement': false,
            'unique': true,
            'defaultValue': null,
            'primaryKey': false,
            'relatedTableName': '_Left',
            'relatedColumnName': 'id',
            'deleteRule': 'nullify',
            'indexed': true
          });
    });
  });

  group("Constructors work appropriately", () {
    test("Encoding/decoding is pristine", () {
      var dataModel = ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = Schema.fromDataModel(dataModel);
      var newSchema = Schema.fromMap(baseSchema.asMap());
      expect(newSchema.differenceFrom(baseSchema).hasDifferences, false);
      expect(baseSchema.differenceFrom(newSchema).hasDifferences, false);
    });

    test("Copying is pristine", () {
      var dataModel = ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      var baseSchema = Schema.fromDataModel(dataModel);
      var newSchema = Schema.from(baseSchema);
      expect(newSchema.differenceFrom(baseSchema).hasDifferences, false);
      expect(baseSchema.differenceFrom(newSchema).hasDifferences, false);
    });
  });

  group("Matching", () {
    Schema baseSchema;
    setUp(() {
      var dataModel = ManagedDataModel(
          [LoadedSingleItem, DefaultItem, LoadedItem, Container, Unique]);
      baseSchema = Schema.fromDataModel(dataModel);
    });

    test("Additional table show up as error", () {
      var newSchema = Schema.from(baseSchema);
      newSchema.addTable(SchemaTable("foo", []));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first, contains("'foo' should NOT exist"));
    });

    test("Missing table show up as error", () {
      var newSchema = Schema.from(baseSchema);
      newSchema.removeTable(
          newSchema.tables.firstWhere((t) => t.name == "_DefaultItem"));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first, contains("'_DefaultItem' should exist"));
    });

    test("Same table but renamed shows up as error", () {
      var newSchema = Schema.from(baseSchema);
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
      var newSchema = Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["a", "b", "c"];
      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages, contains(contains("'_Unique' is expected")));
      expect(diff.errorMessages, contains(contains("'a', 'b', 'c'")));

      newSchema = Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["a", "c"];
      diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages, contains(contains("'_Unique' is expected")));
      expect(diff.errorMessages, contains(contains("'a', 'c'")));
    });

    test("Table with same unique, but unordered, shows as equal", () {
      expect(baseSchema.tableForName("_Unique").uniqueColumnSet, ["a", "b"]);

      var newSchema = Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = ["b", "a"];

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, false);
    });

    test("Table with no unique/unique show up as error", () {
      var newSchema = Schema.from(baseSchema);
      newSchema.tableForName("_Unique").uniqueColumnSet = null;
      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages,
          contains(contains("NOT created by migration files")));
      expect(
          diff.errorMessages,
          contains(
              contains("Multi-column unique constraint on table '_Unique'")));

      var nextSchema = Schema.from(newSchema);
      nextSchema.tableForName("_Unique").uniqueColumnSet = ["a", "b"];
      diff = newSchema.differenceFrom(nextSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages,
          contains(contains("is created by migration files")));
      expect(
          diff.errorMessages,
          contains(
              contains("Multi-column unique constraint on table '_Unique'")));
    });

    test("Missing column shows up as error", () {
      var newSchema = Schema.from(baseSchema);
      var t = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem");
      var c = t.columnForName("id");
      t.removeColumn(c);

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          contains("Column 'id' in table '_DefaultItem' should exist"));
    });

    test("Additional column shows up as error", () {
      var newSchema = Schema.from(baseSchema);
      newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .addColumn(SchemaColumn("foo", ManagedPropertyType.integer));

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 1);
      expect(diff.errorMessages.first,
          contains("Column 'foo' in table '_DefaultItem' should NOT exist"));
    });

    test("Same column but with wrong name shows up as error", () {
      var newSchema = Schema.from(baseSchema);
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
      var newSchema = Schema.from(baseSchema);
      var column = newSchema.tables
          .firstWhere((t) => t.name == "_DefaultItem")
          .columns
          .firstWhere((c) => c.name == "id");

      /*
        Note that some properties cannot be diffed because they cannot be changed:
          primary key, type, related table/column name

        These are tested in schema_invalid_difference_test.dart. Anything that can change is accounted
        for here.
       */

      column.isIndexed = !column.isIndexed;
      var diff = baseSchema.differenceFrom(newSchema);
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
      var newSchema = Schema.from(baseSchema);
      newSchema.addTable(SchemaTable("foo", []));
      var df = newSchema.tables.firstWhere((t) => t.name == "_DefaultItem");
      df.addColumn(SchemaColumn("foobar", ManagedPropertyType.integer));
      newSchema
          .tableForName("_LoadedItem")
          .columns
          .firstWhere((sc) => sc.name == "someIndexedThing")
          .isIndexed = false;

      var diff = baseSchema.differenceFrom(newSchema);
      expect(diff.hasDifferences, true);
      expect(diff.errorMessages.length, 3);
      expect(
          diff.errorMessages,
          contains(
              'Column \'someIndexedThing\' in table \'_LoadedItem\' expected \'true\' for \'isIndexed\', but migration files yield \'false\''));
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
      var lowercaseSchema = Schema([
        SchemaTable(
            "table", [SchemaColumn("column", ManagedPropertyType.bigInteger)])
      ]);

      var uppercaseSchema = Schema([
        SchemaTable(
            "TABLE", [SchemaColumn("COLUMN", ManagedPropertyType.bigInteger)])
      ]);

      expect(lowercaseSchema.differenceFrom(uppercaseSchema).hasDifferences,
          false);
    });

    test("A model with an overridden property from a partial", () {
      var dataModel = ManagedDataModel([OverriddenModel]);
      var schema = Schema.fromDataModel(dataModel);
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

  @Relate(Symbol('defaultItems'))
  Container container;
}

class LoadedItem extends ManagedObject<_LoadedItem> {}

class _LoadedItem {
  @primaryKey
  int id;

  @Column(indexed: true)
  String someIndexedThing;

  @Relate(Symbol('loadedItems'),
      onDelete: DeleteRule.restrict, isRequired: false)
  Container container;

  LoadedSingleItem loadedSingleItem;
}

class LoadedSingleItem extends ManagedObject<_LoadedSingleItem> {}

class _LoadedSingleItem {
  @primaryKey
  int id;

  @Relate(Symbol('loadedSingleItem'),
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
  @Column(primaryKey: true, databaseType: ManagedPropertyType.string)
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
      indexed: true)
  int loadedValue;
}

class OverriddenModel extends ManagedObject<_OverriddenModel>
    implements _OverriddenModel {}

class _OverriddenModel extends PartialModel {
  @override
  @Column(indexed: true, unique: true)
  @Validate.oneOf(["a", "b"])
  String field;
}

class PartialModel {
  @primaryKey
  int id;

  @Column(indexed: true)
  String field;
}

class Unique extends ManagedObject<_Unique> implements _Unique {}

@Table.unique([Symbol('a'), Symbol('b')])
class _Unique {
  @primaryKey
  int id;

  String a;
  String b;
  String c;
}

class SelfRef extends ManagedObject<_SelfRef> implements _SelfRef {}

class _SelfRef {
  @primaryKey
  int id;

  String name;

  ManagedSet<SelfRef> children;

  @Relate(#children)
  SelfRef parent;
}

class Left extends ManagedObject<_Left> implements _Left {}

class _Left {
  @primaryKey
  int id;

  String name;

  Right right;

  @Relate(#left)
  Right belongsToRight;
}

class Right extends ManagedObject<_Right> implements _Right {}

class _Right {
  @primaryKey
  int id;

  String name;

  Left left;

  @Relate(#right)
  Left belongsToLeft;
}
