import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../../helpers.dart';

void main() {
  group("Tomany graph", () {
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

    test("Can still get object", () async {
      var q = new UserQuery()
        ..id = 1;
      var user = await q.fetchOne();
      expect(user.id, 1);
      expect(user.name, "Joe");
      expect(user.locations, isNull);

      q = new UserQuery();
      var users = await q.fetch();
      expect(users.length, 5);
    });

    test("Can still fetch objects with foreign keys", () async {
      var q = new LocationQuery()
        ..id = 1;
      var loc = await q.fetchOne();
      expect(loc.id, 1);
      expect(loc.user.id, 1);
      expect(loc.user.name, isNull);
      expect(loc.equipment, isNull);
    });

    test("Keys with same name across table still yields appropriate result", () async {

    });

    test("Can do one level join with single root object", () async {
      var q = new UserQuery()
        ..id = 1
        ..locations = whereAnyMatch;
      var users = await q.fetch();
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
      var users = await q.fetch();
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

    test("Can two level join, multiple root objects", () async {
      var q = new UserQuery()
        ..locations.single.equipment = whereAnyMatch;

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

    test("Can two level join, multiple root objects, predicate on bottom", () async {
      var q = new UserQuery()
        ..locations.single.equipment = [new EquipmentQuery()
          ..id = 1
        ];

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

    test("Can join with predicates on both", () async {
      var q = new LocationQuery()
        ..user = whereRelatedByValue(1)
        ..equipment.single.name = "Fridge";

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

    test("Can join from middle of graph", () async {
      var q = new LocationQuery()
        ..equipment = whereAnyMatch;
      var locations = await q.fetch();

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

      var locations = await q.fetch();
      for (var loc in locations) {
        var u = loc.user;
        expect(u.dynamicBacking.length, 1);
        expect(u.id, 1);
      }
    });

    test("Can fetch graph when omitting foreign or primary keys from query", () async {
      var q = new UserQuery()
        ..resultProperties = ["name"]
        ..locations = [
          new LocationQuery()
            ..resultProperties = ["name"]
        ];

      var users = await q.fetch();
      expect(users.first.name, isNotNull);
      expect(users.first.id, isNotNull);
      expect(users.first.locations.length, greaterThan(0));
      expect(users.first.locations.first.name, isNotNull);
    });
  });

  group("ToOne graph", () {
    ModelContext context = null;

    setUpAll(() async {
      context = await contextWithModels([Owned, Owner]);

      var o = ["A", "B", "C"];
      var owners = await Future.wait(o.map((x) {
        var q = new Query<Owner>()
          ..values.name = x;
        return q.insert();
      }));

      for (var o in owners) {
        if (o.name != "C") {
          var q = new Query<Owned>()
            ..values.name = "${o.name}1"
            ..values.owner = (new Owner()
              ..id = o.id);
          await q.insert();
        }
      }
    });

    tearDownAll(() {
      context?.persistentStore?.close();
    });

    test("Join with single root object", () async {
      var q = new OwnerQuery()
          ..id = 1
          ..owned = whereAnyMatch;
      var o = (await q.fetch()).first.asMap();

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

    test("Join with null value still has key", () async {
      var q = new OwnerQuery()
        ..id = 3
        ..owned = whereAnyMatch;
      var o = (await q.fetch()).first.asMap();

      expect(o, {
        "id" : 3,
        "name" : "C",
        "owned" : null
      });
    });

    test("Join with multi root object", () async {
      var q = new OwnerQuery()
        ..owned = whereAnyMatch;
      var o = await q.fetch();

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
          "id" : 3, "name" : "C", "owned" : null
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
class UserQuery extends ModelQuery<User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;

  @Relationship.hasMany("user")
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
class LocationQuery extends ModelQuery<Location> implements _Location {}
class _Location {
  @primaryKey
  int id;

  String name;

  @Relationship.belongsTo("locations", deleteRule: RelationshipDeleteRule.cascade)
  User user;

  @Relationship.hasMany("location")
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
class EquipmentQuery extends ModelQuery<Equipment> implements Equipment {}
class _Equipment {
  @primaryKey
  int id;

  String name;
  String type;

  @Relationship.belongsTo("equipment", deleteRule: RelationshipDeleteRule.cascade)
  Location location;
}

class Owner extends Model<_Owner> implements _Owner {}
class OwnerQuery extends ModelQuery<Owner> implements _Owner {}
class _Owner {
  @primaryKey
  int id;
  String name;

  @Relationship.hasOne("owner")
  Owned owned;
}

class Owned extends Model<_Owned> implements _Owned {}
class OwnedQuery extends ModelQuery<Owned> implements _Owned {}
class _Owned {
  @primaryKey
  int id;
  String name;

  @Relationship.belongsTo("owned")
  Owner owner;
}