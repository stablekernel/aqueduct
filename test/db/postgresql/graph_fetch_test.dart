import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:async';

void main() {

  test("Graph fetch ensures primary key exists for all objects", () async {
    // Can't join on entities without primary key, if you omit primary key it is automaically added.
    var q = new UserQuery()
      ..resultKeys = ["name"]
      ..locations.single
      ..resultKeys = ["name"];
    print("${q.subQueries}");
  });

  test("Graph fetch ensures foreign key exists for all objects", () async {

  });

  group("Tomany graph", () {
    PostgresModelAdapter adapter;
    List<User> sourceUsers;

    setUpAll(() async {
      adapter = new PostgresModelAdapter.fromConnectionInfo(
          null, "dart", "dart", "localhost", 5432, "dart_test");
      await generateTemporarySchemaFromModels(
          adapter, [User, Equipment, Location]);

      var userNames = ["Joe", "Fred", "Bob", "John", "Sally"];
      // Create a bunch of sample data
      sourceUsers = await Future.wait(userNames.map((name) {
        var q = new Query<User>()
          ..valueObject = (new User()
            ..name = name);
        return q.insert(adapter);
      }));

      var locationCreator = (List<String> names, User u) {
        return names.map((name) {
          var q = new Query<Location>()
            ..valueObject = (new Location()
              ..name = name
              ..user = (new User()
                ..id = u.id));
          return q.insert(adapter);
        });
      };

      sourceUsers[0].locations =
      await Future.wait(locationCreator(["Crestridge", "SK"], sourceUsers[0]));
      sourceUsers[1].locations = await Future.wait(
          locationCreator(["Krog St", "Dumpster"], sourceUsers[1]));
      sourceUsers[2].locations =
      await Future.wait(locationCreator(["Omaha"], sourceUsers[2]));
      sourceUsers[3].locations =
      await Future.wait(locationCreator(["London"], sourceUsers[3]));
      sourceUsers[4].locations = [];

      var equipmentCreator = (List<List<String>> pairs, Location loc) {
        return pairs.map((pair) {
          var q = new Query<Equipment>()
            ..valueObject = (new Equipment()
              ..name = pair.first
              ..type = pair.last
              ..location = (new Location()
                ..id = loc.id));
          return q.insert(adapter);
        });
      };

      sourceUsers[0].locations.first.equipment = await Future.wait(
          equipmentCreator(
              [["Fridge", "Appliance"], ["Microwave", "Appliance"]],
              sourceUsers[0].locations.first));
      sourceUsers[0].locations.last.equipment = await Future.wait(
          equipmentCreator(
              [["Computer", "Electronics"]], sourceUsers[0].locations.last));
      sourceUsers[1].locations.first.equipment = await Future.wait(
          equipmentCreator(
              [["Cash Register", "Admin"]], sourceUsers[1].locations.first));
      sourceUsers[1].locations.last.equipment = [];
      sourceUsers[2].locations.first.equipment = await Future.wait(
          equipmentCreator(
              [["Fire Truck", "Vehicle"]], sourceUsers[2].locations.first));
      sourceUsers[3].locations.first.equipment = [];
    });

    tearDownAll(() {
      adapter.close();
      adapter = null;
    });

    test("Can still get object", () async {
      var q = new UserQuery()
        ..id = 1;
      var user = await q.fetchOne(adapter);
      expect(user.id, 1);
      expect(user.name, "Joe");
      expect(user.locations, isNull);

      q = new UserQuery();
      var users = await q.fetch(adapter);
      expect(users.length, 5);
    });

    test("Can still fetch objects with foreign keys", () async {
      var q = new LocationQuery()
        ..id = 1;
      var loc = await q.fetchOne(adapter);
      expect(loc.id, 1);
      expect(loc.user.id, 1);
      expect(loc.user.name, isNull);
      expect(loc.equipment, isNull);
    });

    test(
        "Keys with same name across table still yields appropriate result", () async {

    });

    test("Can do one level join with single root object", () async {
      var q = new UserQuery()
        ..id = 1
        ..locations = whereAnyMatch;
      var users = await q.fetch(adapter);
      expect(users.length, 1);

      var user = users.first;
      var sourceUserTruncated = new User.fromUser(
          sourceUsers.firstWhere((u) => u.id == 1));
      sourceUserTruncated.locations.first.equipment = null;
      sourceUserTruncated.locations.last.equipment = null;
      expect(user, equals(sourceUserTruncated));

      var map = user.asMap();
      expect(map, {
        "id" : 1,
        "name" : "Joe",
        "locations" : [
          {"id" : 1, "name" : "Crestridge", "user" : {"id" : 1}},
          {"id" : 2, "name" : "SK", "user" : {"id" : 1}},
        ]
      });
    });

    test("Can do one level join with multiple root object", () async {
      var q = new UserQuery()
        ..locations = whereAnyMatch;
      var users = await q.fetch(adapter);
      expect(users.length, 5);

      users.sort((u1, u2) => u1.id - u2.id);

      var sourceUsersTruncuated = sourceUsers.map((u) {
        var uu = new User.fromUser(u);
        uu.locations.forEach((loc) => loc.equipment = null);
        return uu;
      }).toList();

      sourceUsersTruncuated.sort((u1, u2) => u1.id - u2.id);

      for (var i = 0; i < users.length; i++) {
        expect(users[i], equals(sourceUsersTruncuated[i]));
      }

      var mapList = users.map((u) => u.asMap()).toList();
      expect(mapList, [
        {"id" : 1,
        "name" : "Joe",
        "locations" : [
          {"id" : 1, "name" : "Crestridge", "user" : {"id" : 1}},
          {"id" : 2, "name" : "SK", "user" : {"id" : 1}},
        ]},
        {
          "id" : 2,
          "name" : "Fred",
          "locations" : [
            {"id" : 3, "name" : "Krog St", "user" : {"id" : 2}},
            {"id" : 4, "name" : "Dumpster", "user" : {"id" : 2}}
        ]},
        {
          "id" : 3,
          "name" : "Bob",
          "locations" : [
            {"id" : 5, "name" : "Omaha", "user" : {"id" : 3}}
        ]},
        {
          "id" : 4,
          "name" : "John",
          "locations" : [
            {"id" : 6, "name" : "London", "user" : {"id" : 4}}
        ]},
        {
          "id" : 5,
          "name" : "Sally",
          "locations" : []
        }
      ]);
    });

    test("Can two level join, single root object", () async {
      var q = new UserQuery()
        ..id = 1
        ..locations.single.equipment = whereAnyMatch;

      var users = await q.fetch(adapter);
      expect(users.first, equals(sourceUsers.first));

      var map = users.first.asMap();
      expect(map, {
        "id" : 1,
        "name" : "Joe",
        "locations" : [
          {"id" : 1, "name" : "Crestridge", "user" : {"id" : 1}, "equipment" : [
            {"id" : 1, "name" : "Fridge", "type" : "Appliance", "location" : {"id" : 1}},
            {"id" : 2, "name" : "Microwave", "type" : "Appliance", "location" : {"id" : 1}}
          ]},
          {"id" : 2, "name" : "SK", "user" : {"id" : 1}, "equipment" : [
            {"id" : 3, "name" : "Computer", "type" : "Electronics", "location" : {"id" : 2}}
          ]},
        ]
      });

    });

    test("Can two level join, multiple root objects", () async {
      var q = new UserQuery()
        ..locations.single.equipment = whereAnyMatch;

      var users = await q.fetch(adapter);
      expect(users, equals(sourceUsers));

      var mapList = users.map((u) => u.asMap()).toList();
      expect(mapList, [
        {"id" : 1,
          "name" : "Joe",
          "locations" : [
            {"id" : 1, "name" : "Crestridge", "user" : {"id" : 1}, "equipment" : [
              {"id" : 1, "name" : "Fridge", "type" : "Appliance", "location" : {"id" : 1}},
              {"id" : 2, "name" : "Microwave", "type" : "Appliance", "location" : {"id" : 1}}
            ]},
            {"id" : 2, "name" : "SK", "user" : {"id" : 1}, "equipment" : [
              {"id" : 3, "name" : "Computer", "type" : "Electronics", "location" : {"id" : 2}}
            ]},
          ]},
        {
          "id" : 2,
          "name" : "Fred",
          "locations" : [
            {"id" : 3, "name" : "Krog St", "user" : {"id" : 2}, "equipment" : [
              {"id" : 4, "name" : "Cash Register", "type" : "Admin", "location" : {"id" : 3}}
            ]},
            {"id" : 4, "name" : "Dumpster", "user" : {"id" : 2}, "equipment" : []}
          ]},
        {
          "id" : 3,
          "name" : "Bob",
          "locations" : [
            {"id" : 5, "name" : "Omaha", "user" : {"id" : 3}, "equipment" : [
              {"id" : 5, "name" : "Fire Truck", "type" : "Vehicle", "location" : {"id" : 5}}
            ]}
          ]},
        {
          "id" : 4,
          "name" : "John",
          "locations" : [
            {"id" : 6, "name" : "London", "user" : {"id" : 4}, "equipment" : []}
          ]},
        {
          "id" : 5,
          "name" : "Sally",
          "locations" : []
        }
      ]);
    });

    test("Can two level join, multiple root objects, predicate on bottom", () async {
      var q = new UserQuery()
        ..locations.single.equipment = [new EquipmentQuery()
          ..id = 1
        ];

      var users = await q.fetch(adapter);
      var sourceTrunc = sourceUsers.map((u) => new User.fromUser(u)).toList();
      sourceTrunc.forEach((User u) {
        u.locations?.forEach((loc) {
          loc.equipment = loc.equipment?.where((eq) => eq.id == 1)?.toList() ?? [];
        });
      });
      expect(users, equals(sourceTrunc));

      var mapList = users.map((u) => u.asMap()).toList();
      expect(mapList, [
        {"id" : 1,
          "name" : "Joe",
          "locations" : [
            {"id" : 1, "name" : "Crestridge", "user" : {"id" : 1}, "equipment" : [
              {"id" : 1, "name" : "Fridge", "type" : "Appliance", "location" : {"id" : 1}}
            ]},
            {"id" : 2, "name" : "SK", "user" : {"id" : 1}, "equipment" : []},
          ]},
        {
          "id" : 2,
          "name" : "Fred",
          "locations" : [
            {"id" : 3, "name" : "Krog St", "user" : {"id" : 2}, "equipment" : []},
            {"id" : 4, "name" : "Dumpster", "user" : {"id" : 2}, "equipment" : []}
          ]},
        {
          "id" : 3,
          "name" : "Bob",
          "locations" : [
            {"id" : 5, "name" : "Omaha", "user" : {"id" : 3}, "equipment" : []}
          ]},
        {
          "id" : 4,
          "name" : "John",
          "locations" : [
            {"id" : 6, "name" : "London", "user" : {"id" : 4}, "equipment" : []}
          ]},
        {
          "id" : 5,
          "name" : "Sally",
          "locations" : []
        }
      ]);
    });

    test("Can join from middle of graph", () async {
      var q = new LocationQuery()
        ..equipment = whereAnyMatch;
      var locations = await q.fetch(adapter);

      var sourceTrunc = sourceUsers.map((u) => u.locations)
          .expand((l) => l)
          .map((loc) => new Location.fromLocation(loc))
          .toList();
      sourceTrunc.sort((l1, l2) => l1.id - l2.id);
      locations.sort((l1, l2) => l1.id - l2.id);
      expect(locations, equals(sourceTrunc));
    });

    test("Foreign key relationships do not get mirrored in owned object", () async {
      var q = new LocationQuery()
        ..user = whereRelatedByValue(1);

      var locations = await q.fetch(adapter);
      for (var loc in locations) {
        var u = loc.user;
        expect(u.dynamicBacking.length, 1);
        expect(u.id, 1);
      }
    });
  });

  group("ToOne graph", () {
    PostgresModelAdapter adapter;
    List<User> sourceUsers;

    setUpAll(() async {
      new Logger("monadart").onRecord.listen((rec) => print("$rec"));
      adapter = new PostgresModelAdapter.fromConnectionInfo(null, "dart", "dart", "localhost", 5432, "dart_test");
      await generateTemporarySchemaFromModels(adapter, [Owned, Owner]);

      var o = ["A", "B", "C"];
      var owners = await Future.wait(o.map((x) {
        var q = new Query<Owner>()
          ..valueObject = (new Owner()
            ..name = x);
        return q.insert(adapter);
      }));

      for (var o in owners) {
        var q = new Query<Owned>()
            ..valueObject = (new Owned()
              ..name = "${o.name}1"
              ..owner = (new Owner()..id = o.id));
        await q.insert(adapter);
      }
    });

    tearDownAll(() {
      adapter.close();
      adapter = null;
    });

    test("Join with single root object", () async {
      var q = new OwnerQuery()
          ..id = 1
          ..owned = whereAnyMatch;
      var o = (await q.fetch(adapter)).first.asMap();

      expect(o, {
        "id" : 1,
        "name" : "A",
        "owned" : {
          "id" : 1,
          "name" : "A1",
          "owner" : {"id" : 1}
        }
      });
    });

    test("Join with multi root object", () async {
      var q = new OwnerQuery()
        ..owned = whereAnyMatch;
      var o = await q.fetch(adapter);

      var mapList = o.map((x) => x.asMap()).toList();
      expect(mapList, [
        {
          "id" : 1, "name" : "A", "owned" : {
            "id" : 1,
            "name" : "A1",
            "owner" : {"id" : 1}
          }
        },
        {
          "id" : 2, "name" : "B", "owned" : {
            "id" : 2,
            "name" : "B1",
            "owner" : {"id" : 2}
          }
        },
        {
          "id" : 3, "name" : "C", "owned" : {
            "id" : 3,
            "name" : "C1",
            "owner" : {"id" : 3}
          }
        }
      ]);
    });
  });
}

class User extends Model<_User> implements _User {
  User();
  User.fromUser(User u) {
    this
        ..id = u.id
        ..name = u.name
        ..locations = u.locations?.map((l) => new Location.fromLocation(l))?.toList();
  }
  operator == (User other) {
    var propsEqual = this.id == other.id && this.name == other.name;
    if (!propsEqual) {
      return false;
    }

    if(this.locations == null && other.locations == null) {
      return true;
    }

    if(this.locations == null || other.locations == null) {
      return false;
    }

    if (this.locations.length != other.locations.length) {
      return false;
    }
    for (var i = 0; i < this.locations.length; i++) {
      if (this.locations[i] != other.locations[i]) {
        return false;
      }
    }
    return true;
  }
  int get hashCode {
    return this.id;
  }

  String toString() {
    return "User: $id $name L: $locations";
  }
}
class UserQuery extends ModelQuery<User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute.hasMany("user")
  List<Location> locations;
}

class Location extends Model<_Location> implements _Location {
  Location();
  Location.fromLocation(Location loc) {
    this
        ..id = loc.id
        ..name = loc.name
        ..equipment = loc.equipment?.map((eq) => new Equipment.fromEquipment(eq))?.toList()
        ..user = loc.user != null ? (new User()..id = loc.user.id) : null;
  }
  operator == (Location other) {
    var propTruth = this.id == other.id && this.name == other.name && this.user?.id == other.user?.id;
    if (!propTruth) {
      return false;
    }
    if(this.equipment == null && other.equipment == null) {
      return true;
    }
    if(this.equipment == null || other.equipment == null) {
      return false;
    }
    if (this.equipment.length != other.equipment.length) {
      return false;
    }
    for (var i = 0; i < this.equipment.length; i++) {
      if (this.equipment[i] != other.equipment[i]) {
        return false;
      }
    }

    return true;
  }
  int get hashCode {
    return this.id;
  }

  String toString() {
    return "Location: $id $name FK: ${user?.id} EQ: $equipment";
  }
}
class LocationQuery extends ModelQuery<Location> implements _Location {}
class _Location {
  @primaryKey
  int id;

  String name;

  @RelationshipAttribute.belongsTo("locations", deleteRule: RelationshipDeleteRule.cascade)
  User user;

  @RelationshipAttribute.hasMany("location")
  List<Equipment> equipment;
}

class Equipment extends Model<_Equipment> implements _Equipment {
  Equipment();
  Equipment.fromEquipment(Equipment eq) {
    this
        ..id = eq.id
        ..name = eq.name
        ..type = eq.type
        ..location = eq.location != null ? (new Location()..id = eq.location.id) : null;
  }
  int get hashCode {
    return this.id;
  }
  operator == (Equipment other) {
    return this.id == other.id && this.name == other.name && this.type == other.type && this.location?.id == other.location?.id;
  }

  String toString() {
    return "Equipment: $id $name $type FK: ${location.id}";
  }
}
class EquipmentQuery extends ModelQuery<Equipment> implements _Equipment {}
class _Equipment {
  @primaryKey
  int id;

  String name;
  String type;

  @RelationshipAttribute.belongsTo("equipment", deleteRule: RelationshipDeleteRule.cascade)
  Location location;
}

class Owner extends Model<_Owner> implements _Owner {}
class OwnerQuery extends ModelQuery<Owner> implements _Owner {}
class _Owner {
  @primaryKey
  int id;
  String name;

  @RelationshipAttribute.hasOne("owner")
  Owned owned;
}

class Owned extends Model<_Owned> implements _Owned {}
class OwnedQuery extends ModelQuery<Owned> implements _Owned {}
class _Owned {
  @primaryKey
  int id;
  String name;

  @Attributes(nullable: true)
  @RelationshipAttribute.belongsTo("owned")
  Owner owner;
}