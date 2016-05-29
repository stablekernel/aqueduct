import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:mirrors';

void main() {
  group("Valid data model", () {
    var dataModel = new DataModel([User, Item, Manager]);

    test("Entities have appropriate types", () {
      var entity = dataModel.entityForType(User);
      expect(reflectClass(User) == entity.instanceTypeMirror, true);
      expect(reflectClass(_User) == entity.persistentInstanceTypeMirror, true);

      entity = dataModel.entityForType(Item);
      expect(reflectClass(Item) == entity.instanceTypeMirror, true);
      expect(reflectClass(_Item) == entity.persistentInstanceTypeMirror, true);

      entity = dataModel.entityForType(Manager);
      expect(reflectClass(Manager) == entity.instanceTypeMirror, true);
      expect(reflectClass(_Manager) == entity.persistentInstanceTypeMirror, true);
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
      expect(idAttr.type, PropertyType.bigInteger);
      expect(idAttr.autoincrement, true);
      expect(idAttr.name, "id");

      entity = dataModel.entityForType(Item);
      idAttr = entity.attributes[entity.primaryKey];
      expect(idAttr.isPrimaryKey, true);
      expect(idAttr.type, PropertyType.string);
      expect(idAttr.autoincrement, false);
      expect(idAttr.name, "name");
    });

    test("Default properties omit omitted attributes and has* relationships", () {
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
      expect(loadedValue.type, PropertyType.datetime);
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
      expect(relDesc is RelationshipDescription, true);
      expect(relDesc.isNullable, false);
      expect(relDesc.inverseKey, "items");
      expect(relDesc.inverseRelationship == dataModel.entityForType(User).relationships[relDesc.inverseKey], true);
      expect(relDesc.deleteRule, RelationshipDeleteRule.cascade);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, RelationshipType.belongsTo);

      entity = dataModel.entityForType(Manager);
      relDesc = entity.relationships["worker"];
      expect(relDesc is RelationshipDescription, true);
      expect(relDesc.isNullable, true);
      expect(relDesc.inverseKey, "manager");
      expect(relDesc.inverseRelationship == dataModel.entityForType(User).relationships[relDesc.inverseKey], true);
      expect(relDesc.deleteRule, RelationshipDeleteRule.nullify);
      expect(relDesc.destinationEntity == dataModel.entityForType(User), true);
      expect(relDesc.relationshipType, RelationshipType.belongsTo);

      entity = dataModel.entityForType(User);
      relDesc = entity.relationships["manager"];
      expect(relDesc is RelationshipDescription, true);
      expect(relDesc.inverseKey, "worker");
      expect(relDesc.inverseRelationship == dataModel.entityForType(Manager).relationships[relDesc.inverseKey], true);
      expect(relDesc.destinationEntity == dataModel.entityForType(Manager), true);
      expect(relDesc.relationshipType, RelationshipType.hasOne);

      expect(entity.relationships["items"].relationshipType, RelationshipType.hasMany);
    });
  });

  test("Delete rule of setNull throws exception if property is not nullable", () {
    var successful = false;
    try {
      var _ = new DataModel([Owner, FailingChild]);

      successful = true;
    } catch (e) {
      expect(e.message, "Relationship ref on _FailingChild set to nullify on delete, but is not nullable");
    }
    expect(successful, false);
  });
}

class User extends Model<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  String username;
  bool flag;

  @Attributes(nullable: true, defaultValue: "'now()'", unique: true, indexed: true, omitByDefault: true)
  DateTime loadedTimestamp;

  @RelationshipAttribute.hasMany("user")
  List<Item> items;

  @RelationshipAttribute.hasOne("worker")
  Manager manager;
}

class Item extends Model<_Item> implements _Item {}
class _Item {
  @Attributes(primaryKey: true)
  String name;

  @RelationshipAttribute.belongsTo("items", deleteRule: RelationshipDeleteRule.cascade, required: true)
  User user;
}

class Manager extends Model<_Manager> implements _Manager {}
class _Manager {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute.belongsTo("manager")
  User worker;
}

class Owner extends Model<_Owner> implements _Owner {}
class _Owner {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "ref")
  FailingChild gen;
}

class FailingChild extends Model<_FailingChild> implements _FailingChild {}
class _FailingChild {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.belongsTo, "gen", deleteRule: RelationshipDeleteRule.nullify, required: true)
  Owner ref;
}