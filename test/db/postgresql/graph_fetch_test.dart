import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:async';

void main() {
  PostgresModelAdapter adapter;

  setUpAll(() async {
    new Logger("monadart").onRecord.listen((rec) => print("$rec"));
    adapter = new PostgresModelAdapter.fromConnectionInfo(
        null, "dart", "dart", "localhost", 5432, "dart_test");
    await generateTemporarySchemaFromModels(adapter, [User, Equipment, Location]);

    // Create a bunch of sample data

    var userNames = ["Joe", "Fred", "Bob", "John", "Sally"];
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

  test("Can join with one table, get all", () async {
    print("Start");
    var q = new UserQuery()
        ..id = 1
        ..locations = whereAnyMatch;
    var user = (await q.fetch(adapter)).first;
    expect(user.id, 1);
    expect(user.locations.length, 2);
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