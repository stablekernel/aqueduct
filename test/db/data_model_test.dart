import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  group("Valid data model", () {
    ManagedDataModel dataModel;
    setUp(() {
      dataModel = new ManagedDataModel([User, Item, Manager]);
      ManagedContext.defaultContext = new ManagedContext(dataModel, new DefaultPersistentStore());;
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
          relDesc.inverseRelationship ==
              dataModel.entityForType(User).relationships[
                  MirrorSystem.getName(relDesc.inverseKey)],
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
          relDesc.inverseRelationship ==
              dataModel.entityForType(User).relationships[
                  MirrorSystem.getName(relDesc.inverseKey)],
          true);
      expect(relDesc.deleteRule, ManagedRelationshipDeleteRule.nullify);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.belongsTo);

      entity = dataModel.entityForType(User);
      relDesc = entity.relationships["manager"];
      expect(relDesc is ManagedRelationshipDescription, true);
      expect(relDesc.inverseKey, #worker);
      expect(
          relDesc.inverseRelationship ==
              dataModel.entityForType(Manager).relationships[
                  MirrorSystem.getName(relDesc.inverseKey)],
          true);
      expect(
          relDesc.destinationEntity == dataModel.entityForType(Manager), true);
      expect(relDesc.relationshipType, ManagedRelationshipType.hasOne);

      expect(entity.relationships["items"].relationshipType,
          ManagedRelationshipType.hasMany);
    });

    test("Instances created from entity only have mapped elements", () {
      var entity = dataModel.entityForType(User);
      User instance = entity.instanceFromMappingElements(
          [new PersistentColumnMapping(entity.attributes["id"], 2)]);
      expect(instance.id, 2);
      expect(instance.loadedTimestamp, isNull);
      expect(instance.manager, isNull);
      expect(instance.items, isNull);
    });

    test(
        "Instances created from entity contain belongsTo relationships as model objects",
        () {
      var entity = dataModel.entityForType(Item);
      Item instance = entity.instanceFromMappingElements([
        new PersistentColumnMapping(entity.attributes["name"], "foo"),
        new PersistentColumnMapping(entity.relationships["user"], 1)
      ]);
      expect(instance.name, "foo");
      expect(instance.user is User, true);
      expect(instance.user.id, 1);
    });

    test("Instances created from entity omit joined element", () {
      var entity = dataModel.entityForType(User);
      User instance = entity.instanceFromMappingElements([
        new PersistentColumnMapping(entity.attributes["id"], 2),
        new PersistentJoinMapping(
            PersistentJoinType.leftOuter, entity.attributes["items"], null, [
          new PersistentColumnMapping(
              dataModel.entityForType(Item).attributes["name"], "foobar")
        ])
      ]);
      expect(instance.id, 2);
      expect(instance.items, isNull);
    });

  });

  group("Valid data model with deferred types", () {
    test("Entities have correct properties and relationships", () {
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      ManagedContext.defaultContext = new ManagedContext(dataModel, new DefaultPersistentStore());

      expect(dataModel.entities.length, 2);

      var totalEntity = dataModel.entityForType(TotalModel);
      var referenceEntity = dataModel.entityForType(PartialReferenceModel);

      expect(totalEntity.properties.length, 5);
      expect(totalEntity.primaryKey, "id");
      expect(totalEntity.attributes["transient"].isTransient, true);
      expect(totalEntity.attributes["addedField"].name, isNotNull);
      expect(totalEntity.attributes["id"].isPrimaryKey, true);
      expect(totalEntity.attributes["field"].isIndexed, true);
      expect(totalEntity.relationships["relationship"].destinationEntity.tableName, referenceEntity.tableName);
      expect(totalEntity.relationships["relationship"].relationshipType, ManagedRelationshipType.hasMany);

      expect(referenceEntity.relationships["relationship"].destinationEntity.tableName, totalEntity.tableName);
    });

    test("Will use tableName of base class if not declared in subclass", () {
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      ManagedContext.defaultContext = new ManagedContext(dataModel, new DefaultPersistentStore());
      expect(dataModel.entityForType(TotalModel).tableName, "predefined");
    });

    test("Order of partial data model doesn't matter when related", () {
      var dm1 = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      var dm2 = new ManagedDataModel([PartialReferenceModel, TotalModel]);
      expect(dm1.entities.map((e) => e.tableName).contains("predefined"), true);
      expect(dm1.entities.map((e) => e.tableName).contains("_PartialReferenceModel"), true);
      expect(dm2.entities.map((e) => e.tableName).contains("predefined"), true);
      expect(dm2.entities.map((e) => e.tableName).contains("_PartialReferenceModel"), true);
    });

    test("Partials have defaultProperties from persistent type superclasses", () {
      var dataModel = new ManagedDataModel([TotalModel, PartialReferenceModel]);
      var defaultProperties = dataModel.entityForType(TotalModel).defaultProperties;
      expect(defaultProperties.contains("id"), true);
      expect(defaultProperties.contains("field"), true);
      expect(defaultProperties.contains("addedField"), true);

      expect(dataModel.entityForType(PartialReferenceModel).defaultProperties.contains("relationship"), true);
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
      expect(e.message, contains("Class '_NoPrimaryKey' doesn't declare a primary key property"));
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
      expect(e.message, contains("Property 'uri' on '_InvalidModel' has an unsupported type"));
    }
  });

  test("Model with unsupported transient property type fails on compilation",
      () {
    try {
      new ManagedDataModel([InvalidTransientModel]);
      expect(true, false);
    } on ManagedDataModelException catch (e) {
      expect(e.message, startsWith("Property 'uri' on '_InvalidTransientModel' has an unsupported type"));
    }
  });

  group("Schema generation", () {
    ManagedDataModel dataModel;

    setUp(() {
      dataModel = new ManagedDataModel([User, Item, Manager]);
      ManagedContext.defaultContext = new ManagedContext(dataModel, new DefaultPersistentStore());;
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
  void set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @managedTransientInputAttribute
  void set inputOnly(String s) {
    text = s;
  }

  @managedTransientOutputAttribute
  String get outputOnly => text;
  void set outputOnly(String s) {
    text = s;
  }

  // This is intentionally invalid
  @managedTransientInputAttribute
  String get invalidInput => text;

  // This is intentionally invalid
  @managedTransientOutputAttribute
  void set invalidOutput(String s) {
    text = s;
  }

  @managedTransientAttribute
  String get bothButOnlyOnOne => text;
  void set bothButOnlyOnOne(String s) {
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
  void set bothOverQualified(String s) {
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

class PartialModel {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String field;

  ManagedSet<PartialReferenceModel> relationship;

  static String tableName() {
    return "predefined";
  }
}

class PartialReferenceModel extends ManagedObject<_PartialReferenceModel> implements _PartialReferenceModel {}
class _PartialReferenceModel {
  @managedPrimaryKey
  int id;

  String field;

  @ManagedRelationship.deferred(ManagedRelationshipDeleteRule.cascade, isRequired: true)
  PartialModel relationship;
}