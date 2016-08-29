import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:mirrors';

void main() {
  var ps = new DefaultPersistentStore();
  DataModel dm = new DataModel([TransientTest, User, Post]);
  ModelContext _ = new ModelContext(dm, ps);

  test("NoSuchMethod still throws", () {
    var user = new User();
    try {
      reflect(user).invoke(#foo, []);

      expect(true, false);
    } on NoSuchMethodError {}

  });

  test("Model object construction", () {
    var user = new User();
    user.name = "Joe";
    user.id = 1;

    expect(user.name, "Joe");
    expect(user.id, 1);
  });


  test("Mismatched type throws exception", () {
    var user = new User();
    try {
      reflect(user).setField(#name, 1);

      expect(true, false);
    } on DataModelException catch (e) {
      expect(e.message, "Type mismatch for property name on _User, expected assignable type matching PropertyType.string but got _Smi.");
    }

    try {
      reflect(user).setField(#id, "foo");
    } on DataModelException catch (e) {
      expect(e.message, "Type mismatch for property id on _User, expected assignable type matching PropertyType.integer but got _OneByteString.");
    }
  });

  test("Accessing model object without field should return null", () {
    var user = new User();
    expect(user.name, isNull);
  });

  test("Getting/setting property that is undeclared throws exception", () {
    var user = new User();

    try {
      reflect(user).getField(#foo);
      expect(true, false);
    } on DataModelException catch (e) {
      expect(e.message, "Model type User has no property foo.");
    }

    try {
      reflect(user).setField(#foo, "hey");
      expect(true, false);
    } on DataModelException catch (e) {
      expect(e.message, "Model type User has no property foo.");
    }
  });

  test("Can assign and read embedded objects", () {
    var user = new User();
    user.id = 1;
    user.name = "Bob";
    var posts = [
      new Post()
        ..text = "A"
        ..id = 1
        ..owner = user,
      new Post()
        ..text = "B"
        ..id = 2
        ..owner = user,
      new Post()
        ..text = "C"
        ..id = 3
        ..owner = user,
    ];

    user.posts = new OrderedSet.from(posts);

    expect(user.posts.length, 3);
    expect(user.posts.first.owner, user);
    expect(user.posts.first.text, "A");

    expect(posts.first.owner, user);
    expect(posts.first.owner.name, "Bob");
  });

  test("Can convert object to map", () {
    var user = new User();
    user.id = 1;
    user.name = "Bob";
    var posts = [
      new Post()
        ..text = "A"
        ..id = 1,
      new Post()
        ..text = "B"
        ..id = 2,
      new Post()
        ..text = "C"
        ..id = 3,
    ];
    user.posts = new OrderedSet.from(posts);

    var m = user.asMap();
    expect(m is Map, true);
    expect(m["id"], 1);
    expect(m["name"], "Bob");
    var mPosts = m["posts"];
    expect(mPosts.length, 3);
    expect(mPosts.first["id"], 1);
    expect(mPosts.first["text"], "A");
    expect(mPosts.first["owner"], null);
  });

  test("Can read from map", () {
    var map = {"id": 1, "name": "Bob"};

    var postMap = [
      {"text": "hey", "id": 1},
      {"text": "ho", "id": 2}
    ];

    var user = new User();
    user.readMap(map);

    expect(user.id, 1);
    expect(user.name, "Bob");

    var posts = postMap.map((e) => new Post()..readMap(e)).toList();
    expect(posts[0].id, 1);
    expect(posts[1].id, 2);
    expect(posts[0].text, "hey");
    expect(posts[1].text, "ho");
  });

  test("Reading from map with bad key fails", () {
    var map = {"id": 1, "name": "Bob", "bad_key": "value"};

    var user = new User();
    var successful = false;
    try {
      user.readMap(map);
      successful = true;
    } catch (e) {
      expect(e.message, "Key bad_key does not exist for User");
    }
    expect(successful, false);
  });

  test("Handles DateTime conversion", () {
    var dateString = "2000-01-01T05:05:05.010Z";
    var map = {"id": 1, "name": "Bob", "dateCreated": dateString};
    var user = new User();
    user.readMap(map);

    expect(
        user.dateCreated.difference(DateTime.parse(dateString)), Duration.ZERO);

    var remap = user.asMap();
    expect(remap["dateCreated"], dateString);
  });

  test("Reads embeded object", () {
    var postMap = {
      "text": "hey",
      "id": 1,
      "owner": {"name": "Alex", "id": 18}
    };
    var post = new Post()..readMap(postMap);
    expect(post.text, "hey");
    expect(post.id, 1);
    expect(post.owner.id, 18);
    expect(post.owner.name, "Alex");
  });

  test("Trying to read embedded object that isnt an object fails", () {
    var postMap = {"text": "hey", "id": 1, "owner": 12};
    var post = new Post();
    var successful = false;
    try {
      post.readMap(postMap);
      successful = true;
    } catch (e) {
      expect(e.message, "Expecting a Map for User in the owner field, got 12 instead.");
    }
    expect(successful, false);
  });

  test("Setting embeded object to null doesn't throw exception", () {
    var post = new Post()
      ..id = 4
      ..owner = (new User()
        ..id = 3
        ..name = "Alex");
    post.owner = null;
    expect(post.owner, isNull);
  });

  test("Setting properties to null is OK", () {
    var u = new User();
    u.name = "Bob";
    u.dateCreated = null;
    u.name = null; // I previously set this to a value on purpose and then reset it to null

    expect(u.name, isNull);
    expect(u.dateCreated, isNull);
  });

  test("Primary key works", () {
    var u = new User();
    expect(u.entity.primaryKey, "id");

    var p = new Post();
    expect(p.entity.primaryKey, "id");
  });

  test("Mappable properties are handled in readMap and asMap", () {
    var t = new TransientTest();
    t.id = 1;
    t.text = "Bob";
    var m = t.asMap();
    expect(m["id"], 1);
    expect(m["text"], "Bob");
    expect(m["defaultedText"], "Mr. Bob");

    m["defaultedText"] = "Mr. Fred";
    t.readMap(m);
    expect(t.defaultedText, "Mr. Fred");
    expect(t.text, "Fred");
    expect(t.id, 1);

    var u = new User();
    u.readMap({
      "value" : "Foo",
      "name" : "Bob",
      "id" : 1,
      "dateCreated" : "2000-01-01T00:00:00Z"
    });

    expect(u.value, "Foo");
    expect(u.name, "Bob");

    u = new User()
      ..id = 1;
    var um = u.asMap();
    expect(um["values"], null);
    expect(um["id"], 1);
    expect(um.length, 1);
  });

  test("Mappable properties can be restricted to input/output only", () {
    var t = new TransientTest()..readMap({
      "id" : 1,
      "inputInt" : 2,
      "text" : "foo"
    });
    expect(t.id, 1);
    expect(t.inputInt, 2);

    expect(t.asMap().containsKey("inputInt"), false);

    t.inputInt = 4;
    t.outputInt = 3;
    expect(t.asMap()["outputInt"], 3);

    var successful = false;
    try {
      var _ = new TransientTest()
        ..readMap({
          "outputInt" : 3
        });
      successful = true;
    } catch (e) {
      expect(e is QueryException, true);
      expect(e.message, "Key outputInt does not exist for TransientTest");
    }
    expect(successful, false);
  });

  test("Reading hasMany relationship from JSON succeeds", () {
    var u = new User();
    u.readMap({
      "name" : "Bob",
      "id" : 1,
      "posts" : [
        {"text" : "Hi", "id" : 1}
      ]
    });
    expect(u.posts.length, 1);
    expect(u.posts[0].id, 1);
    expect(u.posts[0].text, "Hi");
  });
}

class User extends Model<_User> implements _User {
  @mappable
  String value;
}

class _User {
  @Attributes(nullable: true)
  String name;

  @Attributes(primaryKey: true)
  int id;

  DateTime dateCreated;

  @Relationship.hasMany("owner")
  OrderedSet<Post> posts;
}

class Post extends Model<_Post> implements _Post {}
class _Post {
  @primaryKey
  int id;

  String text;

  @Relationship.belongsTo("posts")
  User owner;
}

class TransientTest extends Model<_TransientTest> implements _TransientTest {
  @mappableOutput
  String get defaultedText => "Mr. $text";

  @mappableInput
  void set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @mappableInput
  int inputInt;

  @mappableOutput
  int outputInt;
}

class _TransientTest {
  @primaryKey
  int id;

  String text;
}
