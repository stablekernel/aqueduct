import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Valid data model", () {
    ManagedContext context;
    ManagedDataModel dataModel;
    setUp(() {
      dataModel = ManagedDataModel(
          [User, Item, Manager, EnumObject, DocumentObject, AnnotatedTable]);
      context = ManagedContext(dataModel, DefaultPersistentStore());
    });

    tearDown(() async {
      await context.close();
    });

    test("Entities have appropriate types", () {
      var entity = dataModel.entityForType(User);
      expect(User == entity.instanceType, true);
      expect('_User' == entity.tableDefinition, true);

      entity = dataModel.entityForType(Item);
      expect(Item == entity.instanceType, true);
      expect('_Item' == entity.tableDefinition, true);

      entity = dataModel.entityForType(Manager);
      expect(Manager == entity.instanceType, true);
      expect('_Manager' == entity.tableDefinition, true);

      entity = dataModel.entityForType(EnumObject);
      expect(EnumObject == entity.instanceType, true);
      expect('_EnumObject' == entity.tableDefinition, true);
    });

    test("Non-existent entity is null", () {
      expect(dataModel.entityForType(String), isNull);
    });

    test("Can fetch models by instance and table definition", () {
      var e1 = dataModel.entityForType(User);
      var e2 = dataModel.entityForType(_User);
      expect(e1 == e2, true);
    });

    test("All attributes/relationships are in properties", () {
      [User, Manager, Item, EnumObject, DocumentObject].forEach((t) {
        var entity = dataModel.entityForType(t);

        entity.attributes.forEach((key, attr) {
          expect(entity.properties[key] == attr, true);
        });

        entity.relationships.forEach((key, attr) {
          expect(entity.properties[key] == attr, true);
        });
      });
    });

    test("Relationships aren't attributes and vice versa", () {
      expect(dataModel.entityForType(User).relationships["id"], isNull);
      expect(dataModel.entityForType(User).attributes["id"], isNotNull);

      expect(dataModel.entityForType(User).attributes["manager"], isNull);
      expect(dataModel.entityForType(User).relationships["manager"], isNotNull);

      expect(dataModel.entityForType(Manager).attributes["worker"], isNull);
      expect(
          dataModel.entityForType(Manager).relationships["worker"], isNotNull);
    });

    test("Entities have appropriate metadata", () {
      var entity = dataModel.entityForType(User);
      expect(entity.tableName, "_User");
      expect(entity.primaryKey, "id");

      entity = dataModel.entityForType(Item);
      expect(entity.tableName, "_Item");
      expect(entity.primaryKey, "name");
    });

    test("Primary key attributes have appropriate values", () {
      var entity = dataModel.entityForType(User);
      var idAttr = entity.attributes[entity.primaryKey];
      expect(idAttr.isPrimaryKey, true);
      expect(idAttr.type.kind, ManagedPropertyType.bigInteger);
      expect(idAttr.autoincrement, true);
      expect(idAttr.name, "id");

      entity = dataModel.entityForType(Item);
      idAttr = entity.attributes[entity.primaryKey];
      expect(idAttr.isPrimaryKey, true);
      expect(idAttr.type.kind, ManagedPropertyType.string);
      expect(idAttr.autoincrement, false);
      expect(idAttr.name, "name");
    });

    test("Default properties omit omitted attributes and has* relationships",
        () {
      var entity = dataModel.entityForType(User);
      expect(entity.defaultProperties, ["id", "username", "flag"]);
      expect(entity.properties["loadedTimestamp"], isNotNull);
      expect(entity.properties["manager"], isNotNull);
      expect(entity.properties["items"], isNotNull);
    });

    test("Default properties contain belongsTo relationship", () {
      var entity = dataModel.entityForType(Item);
      expect(entity.defaultProperties, ["name", "user"]);
    });

    test("Attributes have appropriate value set", () {
      var entity = dataModel.entityForType(User);
      var loadedValue = entity.attributes["loadedTimestamp"];
      expect(loadedValue.isPrimaryKey, false);
      expect(loadedValue.type.kind, ManagedPropertyType.datetime);
      expect(loadedValue.autoincrement, false);
      expect(loadedValue.name, "loadedTimestamp");
      expect(loadedValue.defaultValue, "'now()'");
      expect(loadedValue.isIndexed, true);
      expect(loadedValue.isNullable, true);
      expect(loadedValue.isUnique, true);
      expect(loadedValue.isIncludedInDefaultResultSet, false);
    });

    test("Relationships have appropriate values set", () {
      var entity = dataModel.entityForType(Item);
      var relDesc = entity.relationships["user"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.isNullable, false);
      expect(relDesc.inverseKey, "items");
      expect(
          relDesc.inverse ==
              dataModel.entityForType(User).relationships[relDesc.inverseKey],
          true);
      expect(relDesc.deleteRule, DeleteRule.cascade);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.belongsTo);

      entity = dataModel.entityForType(Manager);
      relDesc = entity.relationships["worker"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.isNullable, true);
      expect(relDesc.inverseKey, "manager");
      expect(
          relDesc.inverse ==
              dataModel.entityForType(User).relationships[relDesc.inverseKey],
          true);
      expect(relDesc.deleteRule, DeleteRule.nullify);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.belongsTo);

      entity = dataModel.entityForType(User);
      relDesc = entity.relationships["manager"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.inverseKey, "worker");
      expect(
          relDesc.inverse ==
              dataModel
                  .entityForType(Manager)
                  .relationships[relDesc.inverseKey],
          true);
      expect(
          relDesc.destinationEntity == dataModel.entityForType(Manager), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.hasOne);

      expect(entity.relationships["items"].relationshipType,
          ManagedRelationshipType.hasMany);
    });

    test("Enums are string attributes in table definition", () {
      var entity = dataModel.entityForType(EnumObject);
      expect(entity.attributes["enumValues"].type.kind,
          ManagedPropertyType.string);
    });

    test("Document properties are .document", () {
      final entity = dataModel.entityForType(DocumentObject);
      expect(entity.attributes["document"].type.kind,
          ManagedPropertyType.document);
    });

    test(
        "Table names are derived from table definition type, can be overridden by annotation",
        () {
      expect(dataModel.entityForType(User).tableName, "_User");
      expect(dataModel.entityForType(Item).tableName, "_Item");
      expect(dataModel.entityForType(Manager).tableName, "_Manager");
      expect(dataModel.entityForType(EnumObject).tableName, "_EnumObject");
      expect(
          dataModel.entityForType(DocumentObject).tableName, "_DocumentObject");
      expect(dataModel.entityForType(AnnotatedTable).tableName, "foobar");
    });

    test("Managed objects can have foreign key references to one another", () {
      final dm = ManagedDataModel([CyclicLeft, CyclicRight]);

      expect(
          dm
              .entityForType(CyclicLeft)
              .relationships["leftRef"]
              .destinationEntity
              .name,
          "CyclicRight");
      expect(dm.entityForType(CyclicLeft).relationships["leftRef"].inverse.name,
          "from");
      expect(dm.entityForType(CyclicLeft).relationships["leftRef"].isBelongsTo,
          true);
      expect(
          dm
              .entityForType(CyclicLeft)
              .relationships["from"]
              .destinationEntity
              .name,
          "CyclicRight");
      expect(dm.entityForType(CyclicLeft).relationships["from"].inverse.name,
          "rightRef");
      expect(dm.entityForType(CyclicLeft).relationships["from"].isBelongsTo,
          false);

      expect(
          dm
              .entityForType(CyclicRight)
              .relationships["rightRef"]
              .destinationEntity
              .name,
          "CyclicLeft");
      expect(
          dm.entityForType(CyclicRight).relationships["rightRef"].inverse.name,
          "from");
      expect(
          dm.entityForType(CyclicRight).relationships["rightRef"].isBelongsTo,
          true);
      expect(
          dm
              .entityForType(CyclicRight)
              .relationships["from"]
              .destinationEntity
              .name,
          "CyclicLeft");
      expect(dm.entityForType(CyclicRight).relationships["from"].inverse.name,
          "leftRef");
      expect(dm.entityForType(CyclicRight).relationships["from"].isBelongsTo,
          false);
    });

    test("Managed objecs can have foreign key references to themselves", () {
      final dm = ManagedDataModel([SelfReferential]);
      expect(
          dm
              .entityForType(SelfReferential)
              .relationships["parent"]
              .destinationEntity
              .name,
          "SelfReferential");
      expect(
          dm
              .entityForType(SelfReferential)
              .relationships["parent"]
              .inverse
              .name,
          "child");
      expect(
          dm.entityForType(SelfReferential).relationships["parent"].isBelongsTo,
          true);
      expect(
          dm
              .entityForType(SelfReferential)
              .relationships["child"]
              .destinationEntity
              .name,
          "SelfReferential");
      expect(
          dm.entityForType(SelfReferential).relationships["child"].inverse.name,
          "parent");
      expect(
          dm.entityForType(SelfReferential).relationships["child"].isBelongsTo,
          false);
    });
  });

  group("Edge cases", () {
    test("ManagedObject with two foreign keys to same object are distinct", () {
      var model = ManagedDataModel([
        DoubleRelationshipForeignKeyModel,
        DoubleRelationshipHasModel,
        SomeOtherRelationshipModel
      ]);

      var isManyOf = model
          .entityForType(DoubleRelationshipForeignKeyModel)
          .relationships["isManyOf"];
      expect(isManyOf.inverse.name, "hasManyOf");
      expect(isManyOf.destinationEntity.tableName,
          model.entityForType(DoubleRelationshipHasModel).tableName);

      var isOneOf = model
          .entityForType(DoubleRelationshipForeignKeyModel)
          .relationships["isOneOf"];
      expect(isOneOf.inverse.name, "hasOneOf");
      expect(isOneOf.destinationEntity.tableName,
          model.entityForType(DoubleRelationshipHasModel).tableName);
    });

    test(
        "ManagedObject with multiple relationships where one is deferred succeeds in finding relationship",
        () {
      var model = ManagedDataModel([
        DoubleRelationshipForeignKeyModel,
        DoubleRelationshipHasModel,
        SomeOtherRelationshipModel
      ]);

      var partial = model
          .entityForType(DoubleRelationshipForeignKeyModel)
          .relationships["partial"];
      expect(partial.destinationEntity.tableName,
          model.entityForType(SomeOtherRelationshipModel).tableName);
    });
  });

  group("Valid data model with deferred types", () {
    test("Entities have correct properties and relationships", () {
      var dataModel = ManagedDataModel([TotalModel, PartialReferenceModel]);

      expect(dataModel.entities.length, 2);

      var totalEntity = dataModel.entityForType(TotalModel);
      var referenceEntity = dataModel.entityForType(PartialReferenceModel);

      expect(totalEntity.properties.length, 5);
      expect(totalEntity.primaryKey, "id");
      expect(totalEntity.attributes["transient"].isTransient, true);
      expect(totalEntity.attributes["addedField"].name, isNotNull);
      expect(totalEntity.attributes["id"].isPrimaryKey, true);
      expect(totalEntity.attributes["field"].isIndexed, true);
      expect(
          totalEntity
              .relationships["hasManyRelationship"].destinationEntity.tableName,
          referenceEntity.tableName);
      expect(totalEntity.relationships["hasManyRelationship"].relationshipType,
          ManagedRelationshipType.hasMany);

      expect(
          referenceEntity
              .relationships["foreignKeyColumn"].destinationEntity.tableName,
          totalEntity.tableName);
    });

    test("Will use tableName of base class if not declared in subclass", () {
      var dataModel = ManagedDataModel([TotalModel, PartialReferenceModel]);
      expect(dataModel.entityForType(TotalModel).tableName, "predefined");
    });

    test("Order of partial data model doesn't matter when related", () {
      var dm1 = ManagedDataModel([TotalModel, PartialReferenceModel]);
      var dm2 = ManagedDataModel([PartialReferenceModel, TotalModel]);
      expect(dm1.entities.map((e) => e.tableName).contains("predefined"), true);
      expect(
          dm1.entities
              .map((e) => e.tableName)
              .contains("_PartialReferenceModel"),
          true);
      expect(dm2.entities.map((e) => e.tableName).contains("predefined"), true);
      expect(
          dm2.entities
              .map((e) => e.tableName)
              .contains("_PartialReferenceModel"),
          true);
    });

    test("Partials have defaultProperties from table definition superclasses",
        () {
      var dataModel = ManagedDataModel([TotalModel, PartialReferenceModel]);
      var defaultProperties =
          dataModel.entityForType(TotalModel).defaultProperties;
      expect(defaultProperties.contains("id"), true);
      expect(defaultProperties.contains("field"), true);
      expect(defaultProperties.contains("addedField"), true);

      expect(
          dataModel
              .entityForType(PartialReferenceModel)
              .defaultProperties
              .contains("foreignKeyColumn"),
          true);
    });
  });

  test("Transient properties are appropriately added to entity", () {
    var dm = ManagedDataModel([TransientTest]);
    var entity = dm.entityForType(TransientTest);

    expect(entity.attributes["defaultedText"].isTransient, true);
    expect(entity.attributes["inputOnly"].isTransient, true);
    expect(entity.attributes["outputOnly"].isTransient, true);
    expect(entity.attributes["bothButOnlyOnOne"].isTransient, true);
    expect(entity.attributes["inputInt"].isTransient, true);
    expect(entity.attributes["outputInt"].isTransient, true);
    expect(entity.attributes["inOut"].isTransient, true);
    expect(entity.attributes["bothOverQualified"].isTransient, true);

    expect(entity.attributes["invalidInput"], isNull);
    expect(entity.attributes["invalidOutput"], isNull);
    expect(entity.attributes["notAnAttribute"], isNull);
  });

  test(
      "Types with same inverse name for two relationships use type as tie-breaker to determine inverse",
      () {
    var model = ManagedDataModel([LeftMany, JoinMany, RightMany]);

    var joinEntity = model.entityForType(JoinMany);
    expect(
      joinEntity.relationships["left"].destinationEntity.instanceType == LeftMany,
        true);
    expect(joinEntity
      .relationships["right"].destinationEntity.instanceType == RightMany,
        true);
  });

  group("Multi-unique", () {
    test(
        "Add Table to table definition with unique list makes instances unique for those columns",
        () {
      var dm = ManagedDataModel([MultiUnique]);
      var e = dm.entityForType(MultiUnique);

      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["a"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test(
        "Add Table to table definition with unique list makes instances unique for those columns, where column is foreign key relationship",
        () {
      var dm = ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test(
        "Add Table to table definition with unique list makes instances unique for those columns, where column is foreign key relationship",
        () {
      var dm = ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test(
        "Add Table to table definition with unique list makes instances unique for those columns, where column is foreign key relationship",
        () {
      var dm = ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test(
        "Add Table to table definition with unique list makes instances unique for those columns, where column is foreign key relationship",
        () {
      var dm = ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });
  });
}

class User extends ManagedObject<_User> implements _User {
  @Serialize()
  String stringID;
}

class _User {
  @primaryKey
  int id;

  String username;
  bool flag;

  @Column(
      nullable: true,
      defaultValue: "'now()'",
      unique: true,
      indexed: true,
      omitByDefault: true)
  DateTime loadedTimestamp;

  ManagedSet<Item> items;

  Manager manager;
}

class Item extends ManagedObject<_Item> implements _Item {}

class _Item {
  @Column(primaryKey: true)
  String name;

  @Relate(Symbol('items'), onDelete: DeleteRule.cascade, isRequired: true)
  User user;
}

class Manager extends ManagedObject<_Manager> implements _Manager {}

class _Manager {
  @primaryKey
  int id;

  String name;

  @Relate(Symbol('manager'))
  User worker;
}

class TransientTest extends ManagedObject<_TransientTest>
    implements _TransientTest {
  String notAnAttribute;

  @Serialize(input: false, output: true)
  String get defaultedText => "Mr. $text";

  @Serialize(input: true, output: false)
  set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @Serialize(input: true, output: false)
  set inputOnly(String s) {
    text = s;
  }

  @Serialize(input: false, output: true)
  String get outputOnly => text;

  set outputOnly(String s) {
    text = s;
  }

  // This is intentionally invalid
  @Serialize(input: true, output: false)
  String get invalidInput => text;

  // This is intentionally invalid
  @Serialize(input: false, output: true)
  set invalidOutput(String s) {
    text = s;
  }

  @Serialize()
  String get bothButOnlyOnOne => text;

  set bothButOnlyOnOne(String s) {
    text = s;
  }

  @Serialize(input: true, output: false)
  int inputInt;

  @Serialize(input: false, output: true)
  int outputInt;

  @Serialize()
  int inOut;

  @Serialize()
  String get bothOverQualified => text;

  @Serialize()
  set bothOverQualified(String s) {
    text = s;
  }
}

class _TransientTest {
  @primaryKey
  int id;

  String text;
}

class TotalModel extends ManagedObject<_TotalModel> implements _TotalModel {
  @Serialize()
  int transient;
}

class _TotalModel extends PartialModel {
  String addedField;
}

class PartialModel {
  @primaryKey
  int id;

  @Column(indexed: true)
  String field;

  ManagedSet<PartialReferenceModel> hasManyRelationship;

  static String tableName() {
    return "predefined";
  }
}

class PartialReferenceModel extends ManagedObject<_PartialReferenceModel>
    implements _PartialReferenceModel {}

class _PartialReferenceModel {
  @primaryKey
  int id;

  String field;

  @Relate.deferred(DeleteRule.cascade, isRequired: true)
  PartialModel foreignKeyColumn;
}

class DoubleRelationshipForeignKeyModel
    extends ManagedObject<_DoubleRelationshipForeignKeyModel>
    implements _DoubleRelationshipForeignKeyModel {}

class _DoubleRelationshipForeignKeyModel {
  @primaryKey
  int id;

  @Relate(Symbol('hasManyOf'))
  DoubleRelationshipHasModel isManyOf;

  @Relate(Symbol('hasOneOf'))
  DoubleRelationshipHasModel isOneOf;

  @Relate.deferred(DeleteRule.cascade)
  SomeOtherPartialModel partial;
}

class DoubleRelationshipHasModel
    extends ManagedObject<_DoubleRelationshipHasModel>
    implements _DoubleRelationshipHasModel {}

class _DoubleRelationshipHasModel {
  @primaryKey
  int id;

  ManagedSet<DoubleRelationshipForeignKeyModel> hasManyOf;
  DoubleRelationshipForeignKeyModel hasOneOf;
}

class SomeOtherRelationshipModel
    extends ManagedObject<_SomeOtherRelationshipModel> {}

class _SomeOtherRelationshipModel extends SomeOtherPartialModel {
  @primaryKey
  int id;
}

class SomeOtherPartialModel {
  DoubleRelationshipForeignKeyModel deferredRelationship;
}

class LeftMany extends ManagedObject<_LeftMany> implements _LeftMany {}

class _LeftMany {
  @primaryKey
  int id;

  ManagedSet<JoinMany> join;
}

class RightMany extends ManagedObject<_RightMany> implements _RightMany {}

class _RightMany {
  @primaryKey
  int id;

  ManagedSet<JoinMany> join;
}

class JoinMany extends ManagedObject<_JoinMany> implements _JoinMany {}

class _JoinMany {
  @primaryKey
  int id;

  @Relate(Symbol('join'))
  LeftMany left;

  @Relate(Symbol('join'))
  RightMany right;
}

class CyclicLeft extends ManagedObject<_CyclicLeft> {}

class _CyclicLeft {
  @primaryKey
  int id;

  @Relate(Symbol('from'))
  CyclicRight leftRef;

  CyclicRight from;
}

class CyclicRight extends ManagedObject<_CyclicRight> {}

class _CyclicRight {
  @primaryKey
  int id;

  @Relate(Symbol('from'))
  CyclicLeft rightRef;

  CyclicLeft from;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues { abcd, efgh, other18 }

class MultiUnique extends ManagedObject<_MultiUnique> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUnique {
  @primaryKey
  int id;

  int a;
  int b;
}

class MultiUniqueBelongsTo extends ManagedObject<_MultiUniqueBelongsTo> {}

@Table.unique([Symbol('rel'), Symbol('b')])
class _MultiUniqueBelongsTo {
  @primaryKey
  int id;

  @Relate(Symbol('a'))
  MultiUniqueHasA rel;

  String b;
}

class MultiUniqueHasA extends ManagedObject<_MultiUniqueHasA> {}

class _MultiUniqueHasA {
  @primaryKey
  int id;

  MultiUniqueBelongsTo a;
}

class DocumentObject extends ManagedObject<_DocumentObject> {}

class _DocumentObject {
  @primaryKey
  int id;

  Document document;
}

class AnnotatedTable extends ManagedObject<_AnnotatedTable> {}

@Table(name: "foobar")
class _AnnotatedTable {
  @primaryKey
  int id;
}

class SelfReferential extends ManagedObject<_SelfReferential>
    implements _SelfReferential {}

class _SelfReferential {
  @primaryKey
  int id;

  String name;

  @Relate(#child)
  SelfReferential parent;

  SelfReferential child;
}
