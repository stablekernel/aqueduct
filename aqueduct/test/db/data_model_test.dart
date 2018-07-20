import 'dart:mirrors';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group("Valid data model", () {
    ManagedContext context;
    ManagedDataModel dataModel;
    setUp(() {
      dataModel =
          ManagedDataModel([User, Item, Manager, EnumObject, DocumentObject]);
      context = ManagedContext(dataModel, DefaultPersistentStore());
    });

    tearDown(() async {
      await context.close();
    });

    test("Entities have appropriate types", () {
      var entity = dataModel.entityForType(User);
      expect(reflectClass(User) == entity.instanceType, true);
      expect(reflectClass(_User) == entity.tableDefinition, true);

      entity = dataModel.entityForType(Item);
      expect(reflectClass(Item) == entity.instanceType, true);
      expect(reflectClass(_Item) == entity.tableDefinition, true);

      entity = dataModel.entityForType(Manager);
      expect(reflectClass(Manager) == entity.instanceType, true);
      expect(reflectClass(_Manager) == entity.tableDefinition, true);

      entity = dataModel.entityForType(EnumObject);
      expect(reflectClass(EnumObject) == entity.instanceType, true);
      expect(reflectClass(_EnumObject) == entity.tableDefinition, true);
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
      expect(entity.dataModel == dataModel, true);
      expect(entity.primaryKey, "id");

      entity = dataModel.entityForType(Item);
      expect(entity.tableName, "_Item");
      expect(entity.dataModel == dataModel, true);
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
      expect(relDesc.inverseKey, #items);
      expect(
          relDesc.inverse ==
              dataModel
                  .entityForType(User)
                  .relationships[MirrorSystem.getName(relDesc.inverseKey)],
          true);
      expect(relDesc.deleteRule, DeleteRule.cascade);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.belongsTo);

      entity = dataModel.entityForType(Manager);
      relDesc = entity.relationships["worker"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.isNullable, true);
      expect(relDesc.inverseKey, #manager);
      expect(
          relDesc.inverse ==
              dataModel
                  .entityForType(User)
                  .relationships[MirrorSystem.getName(relDesc.inverseKey)],
          true);
      expect(relDesc.deleteRule, DeleteRule.nullify);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.belongsTo);

      entity = dataModel.entityForType(User);
      relDesc = entity.relationships["manager"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.inverseKey, #worker);
      expect(
          relDesc.inverse ==
              dataModel
                  .entityForType(Manager)
                  .relationships[MirrorSystem.getName(relDesc.inverseKey)],
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

    test("Two entities with same tableName should throw exception", () {
      try {
        var _ = ManagedDataModel([SameNameOne, SameNameTwo]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("SameNameOne"));
        expect(e.message, contains("SameNameTwo"));
        expect(e.message, contains("'fo'"));
      }
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

    test("Can override property in partial and modify attrs/validators", () {
      var dataModel =
          ManagedDataModel([OverriddenTotalModel, PartialReferenceModel]);

      var entity = dataModel.entityForType(OverriddenTotalModel);
      var field = entity.attributes["field"];
      expect(field.isUnique, true);
      expect(field.validators.length, 1);
    });
  });

  test("Delete rule of setNull throws exception if property is not nullable",
      () {
    try {
      ManagedDataModel([Owner, FailingChild]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message,
          contains("Relationship 'ref' on '_FailingChild' has both"));
    }
  });

  test("Entity without primary key fails", () {
    try {
      ManagedDataModel([NoPrimaryKey]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(
          e.message,
          contains(
              "Class '_NoPrimaryKey' doesn't declare a primary key property"));
    }
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

  test("Model with unsupported property type fails on compilation", () {
    try {
      ManagedDataModel([InvalidModel]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message, contains("Invalid declaration '_InvalidModel.uri'"));
    }
  });

  test("Model with unsupported transient property type fails on compilation",
      () {
    try {
      ManagedDataModel([InvalidTransientModel]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.message,
          startsWith("Invalid declaration 'InvalidTransientModel.uri'"));
    }
  });

  test(
      "Types with same inverse name for two relationships use type as tie-breaker to determine inverse",
      () {
    var model = ManagedDataModel([LeftMany, JoinMany, RightMany]);

    var joinEntity = model.entityForType(JoinMany);
    expect(
        joinEntity.relationships["left"].destinationEntity.instanceType
            .isSubtypeOf(reflectType(LeftMany)),
        true);
    expect(
        joinEntity.relationships["right"].destinationEntity.instanceType
            .isSubtypeOf(reflectType(RightMany)),
        true);
  });

  group("Error cases", () {
    test("Both properties have Relationship metadata", () {
      try {
        var _ = ManagedDataModel([InvalidCyclicLeft, InvalidCyclicRight]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("InvalidCyclicLeft"));
        expect(e.message, contains("InvalidCyclicRight"));
        expect(e.message, contains("but only one side"));
      }
    });

    test("ManagedObjects cannot have foreign key refs to eachother", () {
      try {
        var _ = ManagedDataModel([CyclicLeft, CyclicRight]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("CyclicLeft"));
        expect(e.message, contains("CyclicRight"));
        expect(e.message, contains("have cyclic relationship properties"));
        expect(e.message, contains("rightRef"));
        expect(e.message, contains("leftRef"));
      }
    });

    test("Model with Relationship and Column fails compilation", () {
      try {
        ManagedDataModel([InvalidMetadata, InvalidMetadata1]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("cannot both have"));
        expect(e.message, contains("InvalidMetadata"));
        expect(e.message, contains("'bar'"));
      }
    });

    test("Managed objects with missing inverses fail compilation", () {
      // This needs to find the probable property
      try {
        ManagedDataModel([MissingInverse1, MissingInverseWrongSymbol]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("has no inverse property"));
        expect(e.message, contains("'inverse'"));
        expect(e.message, contains("'has'"));
      }

      try {
        ManagedDataModel([MissingInverse2, MissingInverseAbsent]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("has no inverse property"));
        expect(e.message, contains("'inverseMany'"));
      }
    });

    test("Duplicate inverse properties fail compilation", () {
      try {
        ManagedDataModel([DupInverse, DupInverseHas]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("has more than one inverse property"));
        expect(e.message, contains("foo,bar"));
      }
    });
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

    test(
        "Add Table to table definition with only single element in unique list throws exception, warns to use Table",
        () {
      try {
        ManagedDataModel([MultiUniqueFailureSingleElement]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message,
            contains("add 'Column(unique: true)' to declaration of 'a'"));
      }
    });

    test(
        "Add Table to table definition with empty unique list throws exception",
        () {
      try {
        ManagedDataModel([MultiUniqueFailureNoElement]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("Must contain two or more attributes"));
      }
    });

    test(
        "Add Table to table definition with non-existent property in unique list throws exception",
        () {
      try {
        ManagedDataModel([MultiUniqueFailureUnknown]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("'a' is not a property of this type"));
      }
    });

    test(
        "Add Table to table definition with has- property in unique list throws exception",
        () {
      try {
        ManagedDataModel([
          MultiUniqueFailureRelationship,
          MultiUniqueFailureRelationshipInverse
        ]);
        expect(true, false);
      } on ManagedDataModelError catch (e) {
        expect(e.message, contains("declares 'a' as unique"));
      }
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

class Owner extends ManagedObject<_Owner> implements _Owner {}

class _Owner {
  @primaryKey
  int id;

  FailingChild gen;
}

class FailingChild extends ManagedObject<_FailingChild>
    implements _FailingChild {}

class _FailingChild {
  @primaryKey
  int id;

  @Relate(Symbol('gen'), onDelete: DeleteRule.nullify, isRequired: true)
  Owner ref;
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

class NoPrimaryKey extends ManagedObject<_NoPrimaryKey>
    implements _NoPrimaryKey {}

class _NoPrimaryKey {
  String foo;
}

class InvalidModel extends ManagedObject<_InvalidModel>
    implements _InvalidModel {}

class _InvalidModel {
  @primaryKey
  int id;

  Uri uri;
}

class InvalidTransientModel extends ManagedObject<_InvalidTransientModel>
    implements _InvalidTransientModel {
  @Serialize()
  Uri uri;
}

class _InvalidTransientModel {
  @primaryKey
  int id;
}

class TotalModel extends ManagedObject<_TotalModel> implements _TotalModel {
  @Serialize()
  int transient;
}

class _TotalModel extends PartialModel {
  String addedField;
}

class OverriddenTotalModel extends ManagedObject<_OverriddenTotalModel>
    implements _OverriddenTotalModel {}

class _OverriddenTotalModel extends PartialModel {
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

class InvalidCyclicLeft extends ManagedObject<_InvalidCyclicLeft> {}

class _InvalidCyclicLeft {
  @primaryKey
  int id;

  @Relate(Symbol('ref'))
  InvalidCyclicRight ref;
}

class InvalidCyclicRight extends ManagedObject<_InvalidCyclicRight> {}

class _InvalidCyclicRight {
  @primaryKey
  int id;

  @Relate(Symbol('ref'))
  InvalidCyclicLeft ref;
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

class SameNameOne extends ManagedObject<_SameNameOne> {}

class _SameNameOne {
  @primaryKey
  int id;

  static String tableName() => "fo";
}

class SameNameTwo extends ManagedObject<_SameNameTwo> {}

class _SameNameTwo {
  @primaryKey
  int id;

  static String tableName() => "fo";
}

class InvalidMetadata extends ManagedObject<_InvalidMetadata> {}

class _InvalidMetadata {
  @Column(primaryKey: true)
  int id;

  @Relate(Symbol('foo'))
  @Column(indexed: true)
  InvalidMetadata1 bar;
}

class InvalidMetadata1 extends ManagedObject<_InvalidMetadata1> {}

class _InvalidMetadata1 {
  @primaryKey
  int id;

  InvalidMetadata foo;
}

class MissingInverse1 extends ManagedObject<_MissingInverse1> {}

class _MissingInverse1 {
  @primaryKey
  int id;

  MissingInverseWrongSymbol inverse;
}

class MissingInverseWrongSymbol
    extends ManagedObject<_MissingInverseWrongSymbol> {}

class _MissingInverseWrongSymbol {
  @primaryKey
  int id;

  @Relate(Symbol('foobar'))
  MissingInverse1 has;
}

class MissingInverse2 extends ManagedObject<_MissingInverse2> {}

class _MissingInverse2 {
  @primaryKey
  int id;

  ManagedSet<MissingInverseAbsent> inverseMany;
}

class MissingInverseAbsent extends ManagedObject<_MissingInverseAbsent> {}

class _MissingInverseAbsent {
  @primaryKey
  int id;
}

class DupInverseHas extends ManagedObject<_DupInverseHas> {}

class _DupInverseHas {
  @primaryKey
  int id;

  ManagedSet<DupInverse> inverse;
}

class DupInverse extends ManagedObject<_DupInverse> {}

class _DupInverse {
  @primaryKey
  int id;

  @Relate(Symbol('inverse'))
  DupInverseHas foo;

  @Relate(Symbol('inverse'))
  DupInverseHas bar;
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

class MultiUniqueFailureSingleElement
    extends ManagedObject<_MultiUniqueFailureSingleElement> {}

@Table.unique([Symbol('a')])
class _MultiUniqueFailureSingleElement {
  @primaryKey
  int id;

  int a;
}

class MultiUniqueFailureNoElement
    extends ManagedObject<_MultiUniqueFailureNoElement> {}

@Table.unique([])
class _MultiUniqueFailureNoElement {
  @primaryKey
  int id;
}

class MultiUniqueFailureUnknown
    extends ManagedObject<_MultiUniqueFailureUnknown> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUniqueFailureUnknown {
  @primaryKey
  int id;

  int b;
}

class MultiUniqueFailureRelationship
    extends ManagedObject<_MultiUniqueFailureRelationship> {}

@Table.unique([Symbol('a'), Symbol('b')])
class _MultiUniqueFailureRelationship {
  @primaryKey
  int id;

  MultiUniqueFailureRelationshipInverse a;
  int b;
}

class MultiUniqueFailureRelationshipInverse
    extends ManagedObject<_MultiUniqueFailureRelationshipInverse> {}

class _MultiUniqueFailureRelationshipInverse {
  @primaryKey
  int id;

  @Relate(Symbol('a'))
  MultiUniqueFailureRelationship rel;
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
