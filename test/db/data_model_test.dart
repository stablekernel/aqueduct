import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  group("Valid data model", () {
    ManagedDataModel dataModel;
    setUp(() {
      dataModel = new ManagedDataModel([User, Item, Manager, EnumObject]);
      ManagedContext.defaultContext =
          new ManagedContext(dataModel, new DefaultPersistentStore());
    });

    test("Entities have appropriate types", () {
      var entity = dataModel.entityForType(User);
      expect(reflectClass(User) == entity.instanceType, true);
      expect(reflectClass(_User) == entity.persistentType, true);

      entity = dataModel.entityForType(Item);
      expect(reflectClass(Item) == entity.instanceType, true);
      expect(reflectClass(_Item) == entity.persistentType, true);

      entity = dataModel.entityForType(Manager);
      expect(reflectClass(Manager) == entity.instanceType, true);
      expect(reflectClass(_Manager) == entity.persistentType, true);

      entity = dataModel.entityForType(EnumObject);
      expect(reflectClass(EnumObject) == entity.instanceType, true);
      expect(reflectClass(_EnumObject) == entity.persistentType, true);
    });

    test("Non-existent entity is null", () {
      expect(dataModel.entityForType(String), isNull);
    });

    test("Can fetch models by instance and persistent type", () {
      var e1 = dataModel.entityForType(User);
      var e2 = dataModel.entityForType(_User);
      expect(e1 == e2, true);
    });

    test("All attributes/relationships are in properties", () {
      [User, Manager, Item].forEach((t) {
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
      expect(idAttr.type, ManagedPropertyType.bigInteger);
      expect(idAttr.autoincrement, true);
      expect(idAttr.name, "id");

      entity = dataModel.entityForType(Item);
      idAttr = entity.attributes[entity.primaryKey];
      expect(idAttr.isPrimaryKey, true);
      expect(idAttr.type, ManagedPropertyType.string);
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
      expect(loadedValue.type, ManagedPropertyType.datetime);
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
      expect(relDesc.deleteRule, ManagedRelationshipDeleteRule.cascade);
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
      expect(relDesc.deleteRule, ManagedRelationshipDeleteRule.nullify);
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

    test("Enums are string attributes in persistent type", () {
      var entity = dataModel.entityForType(EnumObject);
      expect(entity.attributes["enumValues"].type, ManagedPropertyType.string);
    });
  });

  group("Edge cases", () {
    test("ManagedObject with two foreign keys to same object are distinct", () {
      var model = new ManagedDataModel([
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
      var model = new ManagedDataModel([
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
        var _ = new ManagedDataModel([SameNameOne, SameNameTwo]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("SameNameOne"));
        expect(e.message, contains("SameNameTwo"));
        expect(e.message, contains("'fo'"));
      }
    });
  });

  group("Valid data model with deferred types", () {
    test("Entities have correct properties and relationships", () {
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      ManagedContext.defaultContext =
          new ManagedContext(dataModel, new DefaultPersistentStore());

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
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      ManagedContext.defaultContext =
          new ManagedContext(dataModel, new DefaultPersistentStore());
      expect(dataModel.entityForType(TotalModel).tableName, "predefined");
    });

    test("Order of partial data model doesn't matter when related", () {
      var dm1 = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      var dm2 = new ManagedDataModel([PartialReferenceModel, TotalModel]);
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

    test("Partials have defaultProperties from persistent type superclasses",
        () {
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
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
      var dataModel = new ManagedDataModel([OverriddenTotalModel, PartialReferenceModel]);

      var entity = dataModel.entityForType(OverriddenTotalModel);
      var field = entity.attributes["field"];
      expect(field.isUnique, true);
      expect(field.validators.length, 1);
    });
  });

  test("Delete rule of setNull throws exception if property is not nullable",
      () {
    try {
      new ManagedDataModel([Owner, FailingChild]);
      expect(true, false);
    } on ManagedDataModelException catch (e) {
      expect(e.message,
          contains("Relationship 'ref' on '_FailingChild' has both"));
    }
  });

  test("Entity without primary key fails", () {
    try {
      new ManagedDataModel([NoPrimaryKey]);
      expect(true, false);
    } on ManagedDataModelException catch (e) {
      expect(
          e.message,
          contains(
              "Class '_NoPrimaryKey' doesn't declare a primary key property"));
    }
  });

  test("Transient properties are appropriately added to entity", () {
    var dm = new ManagedDataModel([TransientTest]);
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
      new ManagedDataModel([InvalidModel]);
      expect(true, false);
    } on ManagedDataModelException catch (e) {
      expect(
          e.message,
          contains(
              "Property 'uri' on '_InvalidModel' has an unsupported type"));
    }
  });

  test("Model with unsupported transient property type fails on compilation",
      () {
    try {
      new ManagedDataModel([InvalidTransientModel]);
      expect(true, false);
    } on ManagedDataModelException catch (e) {
      expect(
          e.message,
          startsWith(
              "Property 'uri' on '_InvalidTransientModel' has an unsupported type"));
    }
  });

  test(
      "Types with same inverse name for two relationships use type as tie-breaker to determine inverse",
      () {
    var model = new ManagedDataModel([LeftMany, JoinMany, RightMany]);

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

  group("Schema generation", () {
    ManagedDataModel dataModel;

    setUp(() {
      dataModel = new ManagedDataModel([User, Item, Manager]);
      ManagedContext.defaultContext =
          new ManagedContext(dataModel, new DefaultPersistentStore());
    });

    test("works for a data model", () {
      var entity = dataModel.entityForType(User);

      expect(entity.documentedResponseSchema.title, "User");
      expect(entity.documentedResponseSchema.type, APISchemaObject.TypeObject);
      expect(entity.documentedResponseSchema.properties.isNotEmpty, true);
    });

    test("includes transient properties", () {
      var entity = dataModel.entityForType(User);
      expect(entity.documentedResponseSchema.properties["stringID"].type,
          APISchemaObject.TypeString);
    });

    test("does not include has(One|Many) relationships", () {
      var entity = dataModel.entityForType(User);
      expect(entity.documentedResponseSchema.properties.containsKey("items"),
          false);
      expect(entity.documentedResponseSchema.properties.containsKey("manager"),
          false);
    });

    test("includes belongsTo relationships", () {
      var entity = dataModel.entityForType(Item);
      expect(entity.documentedResponseSchema.properties["user"], isNotNull);

      // Make sure that only primary key is included
      expect(
          entity.documentedResponseSchema.properties["user"].properties["id"],
          isNotNull);
      expect(
          entity.documentedResponseSchema.properties["user"].properties
              .containsKey("username"),
          false);
    });
  });

  group("Error cases", () {
    test("Both properties have ManagedRelationship metadata", () {
      try {
        var _ = new ManagedDataModel([InvalidCyclicLeft, InvalidCyclicRight]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("InvalidCyclicLeft"));
        expect(e.message, contains("InvalidCyclicRight"));
        expect(e.message, contains("but only one side"));
      }
    });

    test("ManagedObjects cannot have foreign key refs to eachother", () {
      try {
        var _ = new ManagedDataModel([CyclicLeft, CyclicRight]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("CyclicLeft"));
        expect(e.message, contains("CyclicRight"));
        expect(e.message, contains("have cyclic relationship properties"));
        expect(e.message, contains("rightRef"));
        expect(e.message, contains("leftRef"));
      }
    });

    test("Model with ManagedRelationship and ManagedColumnAttributes fails compilation", () {
      try {
        new ManagedDataModel([InvalidMetadata, InvalidMetadata1]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("cannot both have"));
        expect(e.message, contains("InvalidMetadata"));
        expect(e.message, contains("'bar'"));
      }
    });

    test("Managed objects with missing inverses fail compilation", () {
      // This needs to find the probable property
      try {
        new ManagedDataModel([MissingInverse1, MissingInverseWrongSymbol]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("has no inverse property"));
        expect(e.message, contains("'inverse'"));
        expect(e.message, contains("'has'"));
      }

      try {
        new ManagedDataModel([MissingInverse2, MissingInverseAbsent]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("has no inverse property"));
        expect(e.message, contains("'inverseMany'"));
      }
    });

    test("Duplicate inverse properties fail compilation", () {
      try {
        new ManagedDataModel([DupInverse, DupInverseHas]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("has more than one inverse property"));
        expect(e.message, contains("foo,bar"));
      }
    });
  });

  group("Multi-unique", () {
    test("Add ManagedTableAttributes to persistent type with unique list makes instances unique for those columns", () {
      var dm = new ManagedDataModel([MultiUnique]);
      var e = dm.entityForType(MultiUnique);

      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["a"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test("Add ManagedTableAttributes to persistent type with unique list makes instances unique for those columns, where column is foreign key relationship", () {
      var dm = new ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test("Add ManagedTableAttributes to persistent type with unique list makes instances unique for those columns, where column is foreign key relationship", () {
      var dm = new ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test("Add ManagedTableAttributes to persistent type with unique list makes instances unique for those columns, where column is foreign key relationship", () {
      var dm = new ManagedDataModel([MultiUniqueBelongsTo, MultiUniqueHasA]);
      var e = dm.entityForType(MultiUniqueBelongsTo);
      expect(e.uniquePropertySet.length, 2);
      expect(e.uniquePropertySet.contains(e.properties["rel"]), true);
      expect(e.uniquePropertySet.contains(e.properties["b"]), true);
    });

    test("Add ManagedTableAttributes to persistent type with only single element in unique list throws exception, warns to use ManagedColumnAttributes", () {
      try {
        new ManagedDataModel([MultiUniqueFailureSingleElement]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("add 'ManagedColumnAttributes(unique: true)' to declaration of 'a'"));
      }
    });

    test("Add ManagedTableAttributes to persistent type with empty unique list throws exception", () {
      try {
        new ManagedDataModel([MultiUniqueFailureNoElement]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("Must contain two or more attributes"));
      }
    });

    test("Add ManagedTableAttributes to persistent type with non-existent property in unique list throws exception", () {
      try {
        new ManagedDataModel([MultiUniqueFailureUnknown]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("'a' is not a property of this type"));
      }
    });

    test("Add ManagedTableAttributes to persistent type with has- property in unique list throws exception", () {
      try {
        new ManagedDataModel([MultiUniqueFailureRelationship, MultiUniqueFailureRelationshipInverse]);
        expect(true, false);
      } on ManagedDataModelException catch (e) {
        expect(e.message, contains("declares 'a' as unique"));
      }
    });
  });
}

class User extends ManagedObject<_User> implements _User {
  @managedTransientAttribute
  String stringID;
}

class _User {
  @managedPrimaryKey
  int id;

  String username;
  bool flag;

  @ManagedColumnAttributes(
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
  @ManagedColumnAttributes(primaryKey: true)
  String name;

  @ManagedRelationship(#items,
      onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  User user;
}

class Manager extends ManagedObject<_Manager> implements _Manager {}

class _Manager {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedRelationship(#manager)
  User worker;
}

class Owner extends ManagedObject<_Owner> implements _Owner {}

class _Owner {
  @managedPrimaryKey
  int id;

  FailingChild gen;
}

class FailingChild extends ManagedObject<_FailingChild>
    implements _FailingChild {}

class _FailingChild {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#gen,
      onDelete: ManagedRelationshipDeleteRule.nullify, isRequired: true)
  Owner ref;
}

class TransientTest extends ManagedObject<_TransientTest>
    implements _TransientTest {
  String notAnAttribute;

  @managedTransientOutputAttribute
  String get defaultedText => "Mr. $text";

  @managedTransientInputAttribute
  set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @managedTransientInputAttribute
  set inputOnly(String s) {
    text = s;
  }

  @managedTransientOutputAttribute
  String get outputOnly => text;
  set outputOnly(String s) {
    text = s;
  }

  // This is intentionally invalid
  @managedTransientInputAttribute
  String get invalidInput => text;

  // This is intentionally invalid
  @managedTransientOutputAttribute
  set invalidOutput(String s) {
    text = s;
  }

  @managedTransientAttribute
  String get bothButOnlyOnOne => text;
  set bothButOnlyOnOne(String s) {
    text = s;
  }

  @managedTransientInputAttribute
  int inputInt;

  @managedTransientOutputAttribute
  int outputInt;

  @managedTransientAttribute
  int inOut;

  @managedTransientAttribute
  String get bothOverQualified => text;
  @managedTransientAttribute
  set bothOverQualified(String s) {
    text = s;
  }
}

class _TransientTest {
  @managedPrimaryKey
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
  @managedPrimaryKey
  int id;

  Uri uri;
}

class InvalidTransientModel extends ManagedObject<_InvalidTransientModel>
    implements _InvalidTransientModel {
  @managedTransientAttribute
  Uri uri;
}

class _InvalidTransientModel {
  @managedPrimaryKey
  int id;
}

class TotalModel extends ManagedObject<_TotalModel> implements _TotalModel {
  @managedTransientAttribute
  int transient;
}

class _TotalModel extends PartialModel {
  String addedField;
}

class OverriddenTotalModel extends ManagedObject<_OverriddenTotalModel> implements _OverriddenTotalModel {}
class _OverriddenTotalModel extends PartialModel {
  @override
  @ManagedColumnAttributes(indexed: true, unique: true)
  @Validate.oneOf(const ["a", "b"])
  String field;
}

class PartialModel {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String field;

  ManagedSet<PartialReferenceModel> hasManyRelationship;

  static String tableName() {
    return "predefined";
  }
}

class PartialReferenceModel extends ManagedObject<_PartialReferenceModel>
    implements _PartialReferenceModel {}

class _PartialReferenceModel {
  @managedPrimaryKey
  int id;

  String field;

  @ManagedRelationship.deferred(ManagedRelationshipDeleteRule.cascade,
      isRequired: true)
  PartialModel foreignKeyColumn;
}

class DoubleRelationshipForeignKeyModel
    extends ManagedObject<_DoubleRelationshipForeignKeyModel>
    implements _DoubleRelationshipForeignKeyModel {}

class _DoubleRelationshipForeignKeyModel {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#hasManyOf)
  DoubleRelationshipHasModel isManyOf;

  @ManagedRelationship(#hasOneOf)
  DoubleRelationshipHasModel isOneOf;

  @ManagedRelationship.deferred(ManagedRelationshipDeleteRule.cascade)
  SomeOtherPartialModel partial;
}

class DoubleRelationshipHasModel
    extends ManagedObject<_DoubleRelationshipHasModel>
    implements _DoubleRelationshipHasModel {}

class _DoubleRelationshipHasModel {
  @managedPrimaryKey
  int id;

  ManagedSet<DoubleRelationshipForeignKeyModel> hasManyOf;
  DoubleRelationshipForeignKeyModel hasOneOf;
}

class SomeOtherRelationshipModel
    extends ManagedObject<_SomeOtherRelationshipModel> {}

class _SomeOtherRelationshipModel extends SomeOtherPartialModel {
  @managedPrimaryKey
  int id;
}

class SomeOtherPartialModel {
  DoubleRelationshipForeignKeyModel deferredRelationship;
}

class LeftMany extends ManagedObject<_LeftMany> implements _LeftMany {}

class _LeftMany {
  @managedPrimaryKey
  int id;

  ManagedSet<JoinMany> join;
}

class RightMany extends ManagedObject<_RightMany> implements _RightMany {}

class _RightMany {
  @managedPrimaryKey
  int id;

  ManagedSet<JoinMany> join;
}

class JoinMany extends ManagedObject<_JoinMany> implements _JoinMany {}

class _JoinMany {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#join)
  LeftMany left;

  @ManagedRelationship(#join)
  RightMany right;
}

class InvalidCyclicLeft extends ManagedObject<_InvalidCyclicLeft> {}
class _InvalidCyclicLeft {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#ref)
  InvalidCyclicRight ref;
}

class InvalidCyclicRight extends ManagedObject<_InvalidCyclicRight> {}
class _InvalidCyclicRight {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#ref)
  InvalidCyclicLeft ref;
}

class CyclicLeft extends ManagedObject<_CyclicLeft> {}
class _CyclicLeft  {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#from)
  CyclicRight leftRef;

  CyclicRight from;
}

class CyclicRight extends ManagedObject<_CyclicRight> {}
class _CyclicRight  {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#from)
  CyclicLeft rightRef;

  CyclicLeft from;
}

class SameNameOne extends ManagedObject<_SameNameOne> {}
class _SameNameOne {
  @managedPrimaryKey
  int id;

  static String tableName() => "fo";
}

class SameNameTwo extends ManagedObject<_SameNameTwo> {}
class _SameNameTwo {
  @managedPrimaryKey
  int id;

  static String tableName() => "fo";
}

class InvalidMetadata extends ManagedObject<_InvalidMetadata> {}
class _InvalidMetadata {
  @ManagedColumnAttributes(primaryKey: true)
  int id;

  @ManagedRelationship(#foo)
  @ManagedColumnAttributes(indexed: true)
  InvalidMetadata1 bar;
}

class InvalidMetadata1 extends ManagedObject<_InvalidMetadata1> {}
class _InvalidMetadata1 {
  @managedPrimaryKey
  int id;

  InvalidMetadata foo;
}

class MissingInverse1 extends ManagedObject<_MissingInverse1> {}
class _MissingInverse1 {
  @managedPrimaryKey
  int id;

  MissingInverseWrongSymbol inverse;
}

class MissingInverseWrongSymbol extends ManagedObject<_MissingInverseWrongSymbol> {}
class _MissingInverseWrongSymbol {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#foobar)
  MissingInverse1 has;
}

class MissingInverse2 extends ManagedObject<_MissingInverse2> {}
class _MissingInverse2 {
  @managedPrimaryKey
  int id;

  ManagedSet<MissingInverseAbsent> inverseMany;
}

class MissingInverseAbsent extends ManagedObject<_MissingInverseAbsent> {}
class _MissingInverseAbsent {
  @managedPrimaryKey
  int id;
}

class DupInverseHas extends ManagedObject<_DupInverseHas> {}
class _DupInverseHas {
  @managedPrimaryKey
  int id;

  ManagedSet<DupInverse> inverse;
}

class DupInverse extends ManagedObject<_DupInverse> {}
class _DupInverse {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#inverse)
  DupInverseHas foo;

  @ManagedRelationship(#inverse)
  DupInverseHas bar;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}
class _EnumObject {
  @managedPrimaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues {
  abcd, efgh, other18
}


class MultiUnique extends ManagedObject<_MultiUnique> {}
@ManagedTableAttributes.unique(const [#a, #b])
class _MultiUnique {
  @managedPrimaryKey
  int id;

  int a;
  int b;
}

class MultiUniqueFailureSingleElement extends ManagedObject<_MultiUniqueFailureSingleElement> {}
@ManagedTableAttributes.unique(const [#a])
class _MultiUniqueFailureSingleElement {
  @managedPrimaryKey
  int id;

  int a;
}

class MultiUniqueFailureNoElement extends ManagedObject<_MultiUniqueFailureNoElement> {}
@ManagedTableAttributes.unique(const [])
class _MultiUniqueFailureNoElement {
  @managedPrimaryKey
  int id;
}

class MultiUniqueFailureUnknown extends ManagedObject<_MultiUniqueFailureUnknown> {}
@ManagedTableAttributes.unique(const [#a, #b])
class _MultiUniqueFailureUnknown {
  @managedPrimaryKey
  int id;

  int b;
}

class MultiUniqueFailureRelationship extends ManagedObject<_MultiUniqueFailureRelationship> {}
@ManagedTableAttributes.unique(const [#a, #b])
class _MultiUniqueFailureRelationship {
  @managedPrimaryKey
  int id;

  MultiUniqueFailureRelationshipInverse a;
  int b;
}

class MultiUniqueFailureRelationshipInverse extends ManagedObject<_MultiUniqueFailureRelationshipInverse> {}
class _MultiUniqueFailureRelationshipInverse {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#a)
  MultiUniqueFailureRelationship rel;
}

class MultiUniqueBelongsTo extends ManagedObject<_MultiUniqueBelongsTo> {}
@ManagedTableAttributes.unique(const [#rel, #b])
class _MultiUniqueBelongsTo {
  @managedPrimaryKey
  int id;

  @ManagedRelationship(#a)
  MultiUniqueHasA rel;

  String b;
}

class MultiUniqueHasA extends ManagedObject<_MultiUniqueHasA> {}
class _MultiUniqueHasA {
  @managedPrimaryKey
  int id;

  MultiUniqueBelongsTo a;
}