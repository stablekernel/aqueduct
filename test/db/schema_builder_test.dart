import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Alterations", () {
    SchemaBuilder builder;
    setUp(() {
      var dataModel = new DataModel([LoadedSingleItem, DefaultItem, LoadedItem, Container]);
      Schema baseSchema = new Schema.fromDataModel(dataModel);
      builder = new SchemaBuilder(null, baseSchema);
    });

    test("Adding a table", () {
      builder.createTable(new SchemaTable("foobar", []));
      expect(builder.schema.tables.firstWhere((st) => st.name == "foobar"), isNotNull);

      try {
        builder.createTable(new SchemaTable("foobar", []));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("already exists"));
      }

      try {
        builder.createTable(new SchemaTable("_defaultITEM", []));
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
      expect(builder.schema.tables.firstWhere((st) => st.name == "_DefaultItem", orElse: () => null), isNull);

      builder.deleteTable("_cONTAINER");
      expect(builder.schema.tables.firstWhere((st) => st.name == "_Container", orElse: () => null), isNull);
    });

    test("Adding column", () {
      builder.addColumn("_DefaultItem", new SchemaColumn("col1", PropertyType.integer));
      builder.addColumn("_defaultITEM", new SchemaColumn("col2", PropertyType.integer));
      expect(builder.schema.tableForName("_DefaultItem").columns.firstWhere((sc) => sc.name == "col1"), isNotNull);
      expect(builder.schema.tableForName("_DefaultItem").columns.firstWhere((sc) => sc.name == "col2"), isNotNull);

      try {
        builder.addColumn("_DefaultItem", new SchemaColumn("col1", PropertyType.integer));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("already exists"));
      }

      try {
        builder.addColumn("foobar", new SchemaColumn("col3", PropertyType.integer));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }
    });

    test("Deleting column", () {
      builder.deleteColumn("_DefaultItem", "id");
      expect(builder.schema.tableForName("_DefaultItem").columns.firstWhere((sc) => sc.name == "id", orElse: () => null), isNull);

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
        builder.alterColumn("_Container", "defaultItem", ((c) {}));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      try {
        builder.alterColumn("_DefaultItem", "foo", ((c) {}));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      try {
        builder.alterColumn("foobar", "id", ((c) {}));
        expect(true, false);
      } on SchemaException catch (e) {
        expect(e.message, contains("does not exist"));
      }

      // This also tests case sensitivity
      try {
        builder.alterColumn("_defaultITEM", "id", (c) {
          c.type = PropertyType.boolean;
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

      try {
        builder.alterColumn("_LoadedItem", "someIndexedThing", (c) {
          c.isNullable = true;
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
        c.deleteRule = RelationshipDeleteRule.setDefault;
      }, unencodedInitialValue: "'foo'");

      expect(builder.schema.tableForName("_LoadedItem").columnForName("someIndexedThing").isIndexed, false);
      expect(builder.schema.tableForName("_LoadedItem").columnForName("someIndexedThing").isNullable, true);
      expect(builder.schema.tableForName("_LoadedItem").columnForName("someIndexedThing").isUnique, true);
      expect(builder.schema.tableForName("_LoadedItem").columnForName("someIndexedThing").defaultValue, "'bar'");
      expect(builder.schema.tableForName("_LoadedItem").columnForName("someIndexedThing").deleteRule, RelationshipDeleteRule.setDefault);
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