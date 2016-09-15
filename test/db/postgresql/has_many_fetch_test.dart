import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../../helpers.dart';

void main() {
  group("HasMany relationships", () {
    ModelContext context = null;
    List<User> sourceUsers;

    setUpAll(() async {
      context = await contextWithModels([User, Equipment, Location]);

      var userNames = ["Joe", "Fred", "Bob", "John", "Sally"];
      // Create a bunch of sample data
      sourceUsers = await Future.wait(userNames.map((name) {
        var q = new Query<User>()
          ..values.name = name;
        return q.insert();
      }));

      var locationCreator = (List<String> names, User u) {
        return names.map((name) {
          var q = new Query<Location>()
            ..values.name = name
            ..values.user = (new User()..id = u.id);
          return q.insert();
        });
      };

      sourceUsers[0].locations = new OrderedSet.from(await Future.wait(locationCreator(["Crestridge", "SK"], sourceUsers[0])));
      sourceUsers[1].locations = new OrderedSet.from(await Future.wait(locationCreator(["Krog St", "Dumpster"], sourceUsers[1])));
      sourceUsers[2].locations = new OrderedSet.from(await Future.wait(locationCreator(["Omaha"], sourceUsers[2])));
      sourceUsers[3].locations = new OrderedSet.from(await Future.wait(locationCreator(["London"], sourceUsers[3])));
      sourceUsers[4].locations = new OrderedSet();

      var equipmentCreator = (List<List<String>> pairs, Location loc) {
        return pairs.map((pair) {
          var q = new Query<Equipment>()
            ..values.name = pair.first
            ..values.type = pair.last
            ..values.location = (new Location()..id = loc.id);
          return q.insert();
        });
      };

      sourceUsers[0].locations.first.equipment = new OrderedSet.from(await Future.wait(
          equipmentCreator([["Fridge", "Appliance"], ["Microwave", "Appliance"]], sourceUsers[0].locations.first)));
      sourceUsers[0].locations.last.equipment = new OrderedSet.from(await Future.wait(
          equipmentCreator([["Computer", "Electronics"]], sourceUsers[0].locations.last)));
      sourceUsers[1].locations.first.equipment = new OrderedSet.from(await Future.wait(
          equipmentCreator([["Cash Register", "Admin"]], sourceUsers[1].locations.first)));

      sourceUsers[1].locations.last.equipment = new OrderedSet();

      sourceUsers[2].locations.first.equipment = new OrderedSet.from(await Future.wait(
          equipmentCreator([["Fire Truck", "Vehicle"]], sourceUsers[2].locations.first)));
      sourceUsers[3].locations.first.equipment = new OrderedSet();
    });

    tearDownAll(() {
      context?.persistentStore?.close();
      context = null;
    });

    test("Can fetch an object by using matchOn and a MatcherExpression", () async {
      var q = new Query<User>()
        ..matchOn.id = whereEqualTo(1);

      var user = await q.fetchOne();
      expect(user.id, 1);
      expect(user.name, "Joe");
      expect(user.locations, isNull);

      q = new Query<User>();
      var users = await q.fetch();
      expect(users.length, sourceUsers.length);
    });

    test("Can fetch object by specifying a non-MatcherExpression value in matchOn", () async {
      var q = new Query<Location>()
        ..matchOn.id = 1;

      var loc = await q.fetchOne();
      expect(loc.id, 1);
      expect(loc.user.id, 1);
      expect(loc.user.name, isNull);
      expect(loc.equipment, isNull);
    });

    test("Objects returned in join are not the same instance", () async {
      var q = new Query<User>()
        ..matchOn.id = 1
        ..matchOn.locations.includeInResultSet = true;

      var o = await q.fetchOne();
      expect(identical(o.locations.first.user, o), false);
    });

    test("Setting predicate on root object and including subobject returns a single object and its subobjects", () async {
      var q = new Query<User>()
        ..matchOn.id = 1
        ..matchOn.locations.includeInResultSet = true;

      var users = await q.fetch();
      expect(users.length, 1);

      var user = users.first;
      var sourceUserTruncated = new User.fromUser(sourceUsers.firstWhere((u) => u.id == 1));
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

    test("Fetching multiple instances of root type and including subobjects returns entire object graph", () async {
      var q = new Query<User>()
        ..matchOn.locations.includeInResultSet = true;
      var users = await q.fetch();
      expect(users.length, sourceUsers.length);

      users.sort((u1, u2) => u1.id - u2.id);

      var sourceUsersTruncated = sourceUsers.map((u) {
        var uu = new User.fromUser(u);
        uu.locations.forEach((loc) => loc.equipment = null);
        return uu;
      }).toList();

      sourceUsersTruncated.sort((u1, u2) => u1.id - u2.id);

      for (var i = 0; i < users.length; i++) {
        expect(users[i], equals(sourceUsersTruncated[i]));
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

    test("Fetching root type with predicate and two-levels of joins returns that one object, all of its subobjects and subobject's subobjeccts", () async {
      var q = new Query<User>()
        ..matchOn.id = 1
        ..matchOn.locations.includeInResultSet = true
        ..matchOn.locations.matchOn.equipment.includeInResultSet = true;

      var users = await q.fetch();
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

    test("Fetching root type without predicate and two-levels of joins returns entire object graph", () async {
      var q = new Query<User>()
        ..matchOn.locations.includeInResultSet = true
        ..matchOn.locations.matchOn.equipment.includeInResultSet = true;

      var users = await q.fetch();
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

    test("Fetching two-level deep with matcher on the last level will return full object graph until last level", () async {
      var q = new Query<User>()
        ..matchOn.locations.includeInResultSet = true
        ..matchOn.locations.matchOn.equipment.includeInResultSet = true
        ..matchOn.locations.matchOn.equipment.matchOn.id = whereEqualTo(1);

      var users = await q.fetch();
      var sourceTrunc = sourceUsers.map((u) => new User.fromUser(u)).toList();
      sourceTrunc.forEach((User u) {
        u.locations?.forEach((loc) {
          loc.equipment = new OrderedSet.from(loc.equipment?.where((eq) => eq.id == 1) ?? <Equipment>[]);
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

    test("Fetching with join using predicate on both root and subobject filters appropriately", () async {
      var q = new Query<Location>()
        ..matchOn.user = whereRelatedByValue(1)
        ..matchOn.equipment.includeInResultSet = true
        ..matchOn.equipment.matchOn.name = "Fridge";

      var results = await q.fetch();
      var mapList = results.map((u) => u.asMap()).toList();
      expect(mapList, [
        {
          "name" : "Crestridge", "id" : 1, "user" : {"id" : 1}, "equipment" : [
            {"id" : 1, "name" : "Fridge", "type" : "Appliance", "location" : {"id" : 1}}
          ]
        },
        {"name" : "SK", "id" : 2, "user" : {"id" : 1}, "equipment" : []}
      ]);
    });

    test("Can fetch graph when omitting foreign or primary keys from query", () async {
      var q = new Query<User>()
        ..resultProperties = ["name"]
        ..nestedResultProperties[Location] = ["name"]
        ..matchOn.locations.includeInResultSet = true;

      var users = await q.fetch();
      expect(users.first.name, isNotNull);
      expect(users.first.id, isNotNull);
      expect(users.first.locations.length, greaterThan(0));
      expect(users.first.locations.first.name, isNotNull);
    });

    test("Can specify result keys for all joined objects", () async {
      var q = new Query<User>()
        ..resultProperties = ["id"]
        ..nestedResultProperties[Location] = ["id"]
        ..nestedResultProperties[Equipment] = ["id"]
        ..matchOn.locations.includeInResultSet = true
        ..matchOn.locations.matchOn.equipment.includeInResultSet = true;

      var users = await q.fetch();
      expect(users.every((u) {
        return u.backingMap.length == 2 && u.backingMap.containsKey("id") && u.locations.every((l) {
          return l.backingMap.length == 2 && l.backingMap.containsKey("id") && l.equipment.every((eq) {
            return eq.backingMap.length == 1 && eq.backingMap.containsKey("id");
          });
        });
      }), true);
    });
  });
}

class User extends Model<_User> implements _User {
  User();
  User.fromUser(User u) {
    this
      ..id = u.id
      ..name = u.name
      ..locations = new OrderedSet.from(u.locations?.map((l) => new Location.fromLocation(l)));
  }
  operator == (dynamic o) {
    User other = o;
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
class _User {
  @primaryKey
  int id;

  String name;

  OrderedSet<Location> locations;
}

class Location extends Model<_Location> implements _Location {
  Location();
  Location.fromLocation(Location loc) {
    this
      ..id = loc.id
      ..name = loc.name
      ..equipment = new OrderedSet.from(loc.equipment?.map((eq) => new Equipment.fromEquipment(eq)))
      ..user = loc.user != null ? (new User()..id = loc.user.id) : null;
  }
  operator ==(dynamic o) {
    Location other = o;
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
class _Location {
  @primaryKey
  int id;

  String name;

  @RelationshipInverse(#locations, onDelete: RelationshipDeleteRule.cascade)
  User user;

  OrderedSet<Equipment> equipment;
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
  operator ==(dynamic o) {
    Equipment other = o;
    return this.id == other.id && this.name == other.name && this.type == other.type && this.location?.id == other.location?.id;
  }

  String toString() {
    return "Equipment: $id $name $type FK: ${location.id}";
  }
}
class _Equipment {
  @primaryKey
  int id;

  String name;
  String type;

  @RelationshipInverse(#equipment, onDelete: RelationshipDeleteRule.cascade)
  Location location;
}