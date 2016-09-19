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

  test("Transient properties aren't stored in backing", () {
    var t = new TransientTest();
    t.readMap({"inOut" : 2});
    expect(t.inOut, 2);
    expect(t["inOut"], isNull);
  });

  test("mappableInput properties are read in readMap", () {
    var t = new TransientTest()..readMap({
      "id" : 1,
      "defaultedText" : "bar foo"
    });
    expect(t.id, 1);
    expect(t.text, "foo");
    expect(t.inputInt, isNull);
    expect(t.inOut, isNull);

    t = new TransientTest()..readMap({
      "inputOnly" : "foo"
    });
    expect(t.text, "foo");

    t = new TransientTest()..readMap({
      "inputInt" : 2
    });
    expect(t.inputInt, 2);

    t = new TransientTest()..readMap({
      "inOut" : 2
    });
    expect(t.inOut, 2);

    t = new TransientTest()..readMap({
      "bothOverQualified" : "foo"
    });
    expect(t.text, "foo");
  });

  test("mappableOutput properties are emitted in asMap", () {
    var t = new TransientTest()
      ..text = "foo";

    expect(t.asMap()["defaultedText"], "Mr. foo");
    expect(t.asMap()["outputOnly"], "foo");
    expect(t.asMap()["bothButOnlyOnOne"], "foo");
    expect(t.asMap()["bothOverQualified"], "foo");

    t = new TransientTest()
      ..outputInt = 2;
    expect(t.asMap()["outputInt"], 2);

    t = new TransientTest()
      ..inOut = 2;
    expect(t.asMap()["inOut"], 2);
  });

  test("Transient properties are type checked in readMap", () {
    try {
      new TransientTest()..readMap({
        "id" : 1,
        "defaultedText" : 2
      });

      throw 'Unreachable';
    } on QueryException {}

    try {
      new TransientTest()..readMap({
        "id" : 1,
        "inputInt" : "foo"
      });

      throw 'Unreachable';
    } on QueryException {}
  });

  test("Properties that aren't mappableInput are not read in readMap", () {
    try {
      new TransientTest()..readMap({
        "outputOnly" : "foo"
      });
      throw 'Unreachable';
    } on QueryException {}

    try {
      new TransientTest()..readMap({
        "invalidOutput" : "foo"
      });
      throw 'Unreachable';
    } on QueryException {}

    try {
      new TransientTest()..readMap({
        "invalidInput" : "foo"
      });
      throw 'Unreachable';
    } on QueryException {}

    try {
      new TransientTest()..readMap({
        "bothButOnlyOnOne" : "foo"
      });
      throw 'Unreachable';
    } on QueryException {}

    try {
      new TransientTest()..readMap({
        "outputInt" : "foo"
      });
      throw 'Unreachable';
    } on QueryException {}
  });

  test("mappableOutput properties that are null are not emitted in asMap", () {
    var m = (new TransientTest()
      ..id = 1
      ..text = null
    ).asMap();

    expect(m.length, 3);
    expect(m["id"], 1);
    expect(m["text"], null);
    expect(m["defaultedText"], "Mr. null");
  });

  test("Properties that aren't mappableOutput are not emitted in asMap", () {
    var m = (new TransientTest()
      ..id = 1
      ..text = "foo"
      ..inputInt = 2
    ).asMap();

    expect(m.length, 6);
    expect(m["id"], 1);
    expect(m["text"], "foo");
    expect(m["defaultedText"], "Mr. foo");
    expect(m["outputOnly"], "foo");
    expect(m["bothButOnlyOnOne"], "foo");
    expect(m["bothOverQualified"], "foo");
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

  test("Reading/writing instance property that isn't marked as transient shows up nowhere", () {
    var t = new TransientTest();
    try {
      t.readMap({
        "notAnAttribute" : true
      });
      expect(true, false);
    } on QueryException {}

    t.notAnAttribute = "foo";
    expect(t.asMap().containsKey("notAnAttribute"), false);
  });
}

class User extends Model<_User> implements _User {
  @transientAttribute
  String value;
}

class _User {
  @AttributeHint(nullable: true)
  String name;

  @AttributeHint(primaryKey: true)
  int id;

  DateTime dateCreated;

  OrderedSet<Post> posts;
}

class Post extends Model<_Post> implements _Post {}
class _Post {
  @primaryKey
  int id;

  String text;

  @RelationshipInverse(#posts)
  User owner;
}

class TransientTest extends Model<_TransientTest> implements _TransientTest {
  String notAnAttribute;

  @transientOutputAttribute
  String get defaultedText => "Mr. $text";

  @transientInputAttribute
  void set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @transientInputAttribute
  void set inputOnly(String s) {
    text = s;
  }

  @transientOutputAttribute
  String get outputOnly => text;
  void set outputOnly(String s) {
    text = s;
  }

  // This is intentionally invalid
  @transientInputAttribute
  String get invalidInput => text;

  // This is intentionally invalid
  @transientOutputAttribute
  void set invalidOutput(String s) {
    text = s;
  }

  @transientAttribute
  String get bothButOnlyOnOne => text;
  void set bothButOnlyOnOne(String s) {
    text = s;
  }

  @transientInputAttribute
  int inputInt;

  @transientOutputAttribute
  int outputInt;

  @transientAttribute
  int inOut;

  @transientAttribute
  String get bothOverQualified => text;
  @transientAttribute
  void set bothOverQualified(String s) {
    text = s;
  }
}

class _TransientTest {
  @primaryKey
  int id;

  String text;
}
