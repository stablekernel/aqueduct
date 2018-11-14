import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Alterations", () {
    SchemaBuilder builder;
    setUp(() {
      var dataModel = ManagedDataModel([
        LoadedSingleItem,
        DefaultItem,
        LoadedItem,
        Container,
        ExtensiveModel
      ]);
      Schema baseSchema = Schema.fromDataModel(dataModel);
      builder = SchemaBuilder(null, baseSchema);
    });

    test("Adding a table", () {
      builder.createTable(SchemaTable("foobar", []));
      expect(builder.schema.tables.firstWhere((st) => st.name == "foobar"),
          isNotNull);

      try {
        builder.createTable(SchemaTable("foobar", []));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("already exists"));
      }

      try {
        builder.createTable(SchemaTable("_defaultITEM", []));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("already exists"));
      }
    });

    test("Removing a table", () {
      try {
        builder.deleteTable("foobar");
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      builder.deleteTable("_DefaultItem");
      expect(
          builder.schema.tables.firstWhere((st) => st.name == "_DefaultItem",
              orElse: () => null),
          isNull);

      builder.deleteTable("_cONTAINER");
      expect(
          builder.schema.tables
              .firstWhere((st) => st.name == "_Container", orElse: () => null),
          isNull);
    });

    test("Adding a unique set", () {
      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = ["startDate", "indexedValue"];
      });

      expect(builder.schema.tableForName("_ExtensiveModel").uniqueColumnSet,
          ["indexedValue", "startDate"]);
    });

    test("Removing a unique set", () {
      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = ["startDate", "indexedValue"];
      });
      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = null;
      });

      expect(builder.schema.tableForName("_ExtensiveModel").uniqueColumnSet,
          isNull);
    });

    test("Modifying a unique set", () {
      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = ["startDate", "indexedValue"];
      });
      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = ["startDate", "autoincrementValue"];
      });

      expect(builder.schema.tableForName("_ExtensiveModel").uniqueColumnSet,
          ["autoincrementValue", "startDate"]);

      builder.alterTable("_ExtensiveModel", (t) {
        t.uniqueColumnSet = ["startDate", "autoincrementValue", "indexedValue"];
      });

      expect(builder.schema.tableForName("_ExtensiveModel").uniqueColumnSet,
          ["autoincrementValue", "indexedValue", "startDate"]);
    });

    test("Adding column", () {
      builder.addColumn(
          "_DefaultItem", SchemaColumn("col1", ManagedPropertyType.integer));
      builder.addColumn(
          "_defaultITEM", SchemaColumn("col2", ManagedPropertyType.integer));
      expect(
          builder.schema
              .tableForName("_DefaultItem")
              .columns
              .firstWhere((sc) => sc.name == "col1"),
          isNotNull);
      expect(
          builder.schema
              .tableForName("_DefaultItem")
              .columns
              .firstWhere((sc) => sc.name == "col2"),
          isNotNull);

      try {
        builder.addColumn(
            "_DefaultItem", SchemaColumn("col1", ManagedPropertyType.integer));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("already exists"));
      }

      try {
        builder.addColumn(
            "foobar", SchemaColumn("col3", ManagedPropertyType.integer));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }
    });

    test("Deleting column", () {
      builder.deleteColumn("_DefaultItem", "id");
      expect(
          builder.schema
              .tableForName("_DefaultItem")
              .columns
              .firstWhere((sc) => sc.name == "id", orElse: () => null),
          isNull);

      try {
        builder.deleteColumn("_DefaultItem", "col1");
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      try {
        builder.deleteColumn("foobar", "id");
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }
    });

    test("Altering column", () {
      try {
        builder.alterColumn("_Container", "defaultItem", (c) {});
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      try {
        builder.alterColumn("_DefaultItem", "foo", (c) {});
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      try {
        builder.alterColumn("foobar", "id", (c) {});
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      // This also tests case sensitivity
      try {
        builder.alterColumn("_defaultITEM", "id", (c) {
          c.type = ManagedPropertyType.boolean;
        });
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("May not change"));
      }

      try {
        builder.alterColumn("_defaultItem", "id", (c) {
          c.autoincrement = !c.autoincrement;
        });
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("May not change"));
      }

      try {
        builder.alterColumn("_defaultItem", "id", (c) {
          c.relatedTableName = "foo";
        });
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("May not change"));
      }

      try {
        builder.alterColumn("_defaultItem", "id", (c) {
          c.relatedColumnName = "foo";
        });
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("May not change"));
      }

      builder.alterColumn("_LoadedItem", "someIndexedThing", (c) {
        c.isIndexed = false;
        c.isNullable = true;
        c.isUnique = true;
        c.defaultValue = "'bar'";
        c.deleteRule = DeleteRule.setDefault;
      }, unencodedInitialValue: "'foo'");

      expect(
          builder.schema
              .tableForName("_LoadedItem")
              .columnForName("someIndexedThing")
              .isIndexed,
          false);
      expect(
          builder.schema
              .tableForName("_LoadedItem")
              .columnForName("someIndexedThing")
              .isNullable,
          true);
      expect(
          builder.schema
              .tableForName("_LoadedItem")
              .columnForName("someIndexedThing")
              .isUnique,
          true);
      expect(
          builder.schema
              .tableForName("_LoadedItem")
              .columnForName("someIndexedThing")
              .defaultValue,
          "'bar'");
      expect(
          builder.schema
              .tableForName("_LoadedItem")
              .columnForName("someIndexedThing")
              .deleteRule,
          DeleteRule.setDefault);
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
