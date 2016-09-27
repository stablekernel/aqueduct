import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import '../../helpers.dart';

/*
  The test data is like so:

           A       B       C      D
         /   \     | \     |
        C1    C2  C3  C4  C5
      / | \    |   |
    T1 V1 V2  T2  V3
 */

void main() {
  group("Happy path", () {
    ModelContext context = null;
    List<Parent> truth;
    setUpAll(() async {
      context = await contextWithModels([Child, Parent, Toy, Vaccine]);
      truth = await populate();
    });

    tearDownAll(() async {
      await context?.persistentStore?.close();
    });

    test("Fetch has-many relationship that has none returns empty OrderedSet", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.name = "D";

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.id, isNotNull);
        expect(p.children, []);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-many relationship that is empty returns empty, and deeper nested relationships are ignored even when included", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.children.matchOn.toy.includeInResultSet = true
        ..matchOn.children.matchOn.vaccinations.includeInResultSet = true
        ..matchOn.name = "D";

      var verifier = (Parent p) {
        expect(p.name, "D");
        expect(p.id, isNotNull);
        expect(p.children, []);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-many relationship that is non-empty returns values for scalar properties in subobjects only", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.name = "C";

      var verifier = (Parent p) {
        expect(p.name, "C");
        expect(p.id, isNotNull);
        expect(p.children.first.id, isNotNull);
        expect(p.children.first.name, "C5");
        expect(p.children.first.backingMap.containsKey("toy"), false);
        expect(p.children.first.backingMap.containsKey("vaccinations"), false);
      };
      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-many relationship, include has-one and has-many in that has-many, where bottom of graph has valid object for hasmany but not for hasone", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.children.matchOn.toy.includeInResultSet = true
        ..matchOn.children.matchOn.vaccinations.includeInResultSet = true
        ..matchOn.name = "B";

      var verifier = (Parent p) {
        p.children.sort((c1, c2) => c1.id.compareTo(c2.id));

        expect(p.name, "B");
        expect(p.id, isNotNull);
        expect(p.children.first.id, isNotNull);
        expect(p.children.first.name, "C3");
        expect(p.children.first.backingMap.containsKey("toy"), true);
        expect(p.children.first.toy, isNull);
        expect(p.children.first.vaccinations.length, 1);
        expect(p.children.first.vaccinations.first.id, isNotNull);
        expect(p.children.first.vaccinations.first.kind, "V3");

        expect(p.children.last.id, isNotNull);
        expect(p.children.last.name, "C4");
        expect(p.children.last.backingMap.containsKey("toy"), true);
        expect(p.children.last.toy, isNull);
        expect(p.children.last.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetch has-many relationship, include has-one and has-many in that has-many, where bottom of graph has valid object for hasone but not for hasmany", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.children.matchOn.toy.includeInResultSet = true
        ..matchOn.children.matchOn.vaccinations.includeInResultSet = true
        ..matchOn.name = "A";

      var verifier = (Parent p) {
        p.children.sort((c1, c2) => c1.id.compareTo(c2.id));
        p.children.first.vaccinations.sort((v1, v2) => v1.id.compareTo(v2.id));

        expect(p.name, "A");
        expect(p.id, isNotNull);
        expect(p.children.first.id, isNotNull);
        expect(p.children.first.name, "C1");
        expect(p.children.first.toy.id, isNotNull);
        expect(p.children.first.toy.name, "T1");
        expect(p.children.first.vaccinations.length, 2);
        expect(p.children.first.vaccinations.first.id, isNotNull);
        expect(p.children.first.vaccinations.first.kind, "V1");
        expect(p.children.first.vaccinations.last.id, isNotNull);
        expect(p.children.first.vaccinations.last.kind, "V2");

        expect(p.children.last.id, isNotNull);
        expect(p.children.last.name, "C2");
        expect(p.children.last.toy.id, isNotNull);
        expect(p.children.last.toy.name, "T2");
        expect(p.children.last.vaccinations, []);
      };

      verifier(await q.fetchOne());
      verifier((await q.fetch()).first);
    });

    test("Fetching multiple top-level instances and including one level of subobjects", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.name = whereIn(["A", "C", "D"]);
      var results = await q.fetch();
      expect(results.length, 3);
      results.sort((p1, p2) => p1.id.compareTo(p2.id));

      expect(results.first.id, isNotNull);
      expect(results.first.name, "A");
      expect(results.first.children.length, 2);
      expect(results.first.children.first.name, "C1");
      expect(results.first.children.first.backingMap.containsKey("toy"), false);
      expect(results.first.children.first.backingMap.containsKey("vaccinations"), false);
      expect(results.first.children.last.name, "C2");
      expect(results.first.children.last.backingMap.containsKey("toy"), false);
      expect(results.first.children.last.backingMap.containsKey("vaccinations"), false);

      expect(results[1].id, isNotNull);
      expect(results[1].name, "C");
      expect(results[1].children.length, 1);
      expect(results[1].children.first.name, "C5");
      expect(results[1].children.first.backingMap.containsKey("toy"), false);
      expect(results[1].children.first.backingMap.containsKey("vaccinations"), false);

      expect(results.last.id, isNotNull);
      expect(results.last.name, "D");
      expect(results.last.children.length, 0);
    });

    test("Fetch entire graph", () async {
      var q = new Query<Parent>()
        ..matchOn.children.includeInResultSet = true
        ..matchOn.children.matchOn.toy.includeInResultSet = true
        ..matchOn.children.matchOn.vaccinations.includeInResultSet = true;
      var all = await q.fetch();

      var originalIterator = truth.iterator;
      for (var p in all) {
        originalIterator.moveNext();
        expect(p.id, originalIterator.current.id);
        expect(p.name, originalIterator.current.name);

        var originalChildrenIterator = p.children.iterator;
        p.children?.forEach((child) {
          originalChildrenIterator.moveNext();
          expect(child.id, originalChildrenIterator.current.id);
          expect(child.name, originalChildrenIterator.current.name);
          expect(child.toy?.id, originalChildrenIterator.current.toy?.id);
          expect(child.toy?.name, originalChildrenIterator.current.toy?.name);

          var vacIter = originalChildrenIterator.current.vaccinations?.iterator ?? <Vaccine>[].iterator;
          child.vaccinations?.forEach((v) {
            vacIter.moveNext();
            expect(v.id, vacIter.current.id);
            expect(v.kind, vacIter.current.kind);
          });
          expect(vacIter.moveNext(), false);
        });
      }
      expect(originalIterator.moveNext(), false);
    });
  });
}

class Parent extends Model<_Parent> implements _Parent {}
class _Parent {
  @primaryKey int id;
  String name;

  OrderedSet<Child> children;
}

class Child extends Model<_Child> implements _Child {}
class _Child {
  @primaryKey int id;
  String name;

  @RelationshipInverse(#children)
  Parent parent;

  Toy toy;

  OrderedSet<Vaccine> vaccinations;
}

class Toy extends Model<_Toy> implements _Toy {}
class _Toy {
  @primaryKey int id;

  String name;

  @RelationshipInverse(#toy)
  Child child;
}

class Vaccine extends Model<_Vaccine> implements _Vaccine {}
class _Vaccine {
  @primaryKey int id;
  String kind;

  @RelationshipInverse(#vaccinations)
  Child child;
}

Future<List<Parent>> populate() async {
  var modelGraph = <Parent>[];
  var parents = [
    new Parent()
      ..name = "A"
      ..children = new OrderedSet<Child>.from([
        new Child()
          ..name = "C1"
          ..toy = (new Toy()..name = "T1")
          ..vaccinations = (new OrderedSet<Vaccine>.from([
            new Vaccine()..kind = "V1",
            new Vaccine()..kind = "V2",
          ])),
        new Child()
          ..name = "C2"
          ..toy = (new Toy()..name = "T2")
      ]),
    new Parent()
      ..name = "B"
      ..children = new OrderedSet<Child>.from([
        new Child()
          ..name = "C3"
          ..vaccinations = (new OrderedSet<Vaccine>.from([
            new Vaccine()..kind = "V3"
          ])),
        new Child()
          ..name = "C4"
      ]),

    new Parent()
      ..name = "C"
      ..children = new OrderedSet<Child>.from([
        new Child()..name = "C5"
      ]),

    new Parent()
      ..name = "D"
  ];

  for (var p in parents) {
    var q = new Query<Parent>()
      ..values.name = p.name;
    var insertedParent = await q.insert();
    modelGraph.add(insertedParent);

    insertedParent.children = new OrderedSet<Child>();
    for (var child in p.children ?? <Child>[]) {
      var childQ = new Query<Child>()
        ..values.name = child.name
        ..values.parent = insertedParent;
      insertedParent.children.add(await childQ.insert());

      if (child.toy != null) {
        var toyQ = new Query<Toy>()
          ..values.name = child.toy.name
          ..values.child = insertedParent.children.last;
        insertedParent.children.last.toy = await toyQ.insert();
      }

      if (child.vaccinations != null) {
        insertedParent.children.last.vaccinations = new OrderedSet<Vaccine>.from(await Future.wait(child.vaccinations.map((v) {
          var vQ = new Query<Vaccine>()
            ..values.kind = v.kind
            ..values.child = insertedParent.children.last;
          return vQ.insert();
        })));
      }
    }
  }

  return modelGraph;
}

/*
////////
////////
////////
 */

void mainf() {
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