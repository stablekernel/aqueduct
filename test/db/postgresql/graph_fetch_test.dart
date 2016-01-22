import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:async';

void main() {
  PostgresModelAdapter adapter;
  var userNames = ["Joe", "Fred", "Bob", "John", "Sally"];

  setUpAll(() async {
    new Logger("monadart").onRecord.listen((rec) => print("$rec"));
    adapter = new PostgresModelAdapter.fromConnectionInfo(
        null, "dart", "dart", "localhost", 5432, "dart_test");
    await generateTemporarySchemaFromModels(adapter, [User, Equipment, Location]);

    // Create a bunch of sample data
    var users = await Future.wait(userNames.map((name) {
      var q = new Query<User>()
          ..valueObject = (new User()..name = name);
      return q.insert(adapter);
    }));

    var locationCreator = (List<String> names, User u) {
      return names.map((name) {
        var q = new Query<Location>()
          ..valueObject = (new Location()
            ..name = name
            ..user = (new User()..id = u.id));
        return q.insert(adapter);
      });
    };

    var joeLocations = await Future.wait(locationCreator(["Crestridge", "SK"], users[0]));
    var fredLocations = await Future.wait(locationCreator(["Krog St", "Dumpster"], users[1]));
    var bobLocations = await Future.wait(locationCreator(["Omaha"], users[2]));
    await Future.wait(locationCreator(["London"], users[3]));

    var equipmentCreator = (List<List<String>> pairs, Location loc) {
      return pairs.map((pair) {
        var q = new Query<Equipment>()
          ..valueObject = (new Equipment()
            ..name = pair.first
            ..type = pair.last
            ..location = (new Location()..id = loc.id));
        return q.insert(adapter);
      });
    };

    await Future.wait(equipmentCreator([["Fridge", "Appliance"], ["Microwave", "Appliance"]], joeLocations.first));
    await Future.wait(equipmentCreator([["Computer", "Electronics"]], joeLocations.last));
    await Future.wait(equipmentCreator([["Cash Register", "Admin"]], fredLocations.first));
    await Future.wait(equipmentCreator([["Fire Truck", "Vehicle"]], bobLocations.first));
  });

  tearDownAll(() {
    adapter.close();
    adapter = null;
  });

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
    expect(loc.equipment, isNull);
  });

  test("Can do one level join with single root object", () async {
    var q = new UserQuery()
        ..id = 1
        ..locations = whereAnyMatch;
    var users = await q.fetch(adapter);
    expect(users.length, 1);

    var user = users.first;
    expect(user.id, 1);
    expect(user.locations.length, 2);
  });

  test("can do onelevel join with multiple root object", () async {
    var q = new UserQuery()
      ..locations = whereAnyMatch;
    var users = await q.fetch(adapter);
    expect(users.length, 5);

    users.sort((u1, u2) => u1.id - u2.id);

    expect(users[0].name, userNames[0]);
    expect(users[0].locations.length, 2);

    expect(users[1].name, userNames[1]);
    expect(users[1].locations.length, 2);

    expect(users[2].name, userNames[2]);
    expect(users[2].locations.length, 1);

    expect(users[3].name, userNames[3]);
    expect(users[3].locations.length, 1);

    expect(users[4].name, userNames[4]);
    expect(users[4].locations, hasLength(0));
  });

  test("Can join two tables", () async {
    fail("NYI");
  });

  test("Cyclic model graph still works", () async {
    fail("NYI");
  });

}

class User extends Model<_User> implements _User {}
class UserQuery extends ModelQuery<User> implements _User {}
class _User {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  @RelationshipAttribute.hasMany("user")
  List<Location> locations;
}

class Location extends Model<_Location> implements _Location {}
class LocationQuery extends ModelQuery<Location> implements _Location {}
class _Location {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  @RelationshipAttribute.belongsTo("locations", deleteRule: RelationshipDeleteRule.cascade)
  User user;

  @RelationshipAttribute.hasMany("location")
  List<Equipment> equipment;
}

class Equipment extends Model<_Equipment> implements _Equipment {}
class EquipmentQuery extends ModelQuery<Equipment> implements _Equipment {}
class _Equipment {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;
  String type;

  @RelationshipAttribute.belongsTo("equipment", deleteRule: RelationshipDeleteRule.cascade)
  Location location;

}