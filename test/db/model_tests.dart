import 'package:monadart/monadart.dart';
import 'package:test/test.dart';

main() {
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
      user.name = 1;
      fail("This should throw an exception.");
    } catch (e) {
      expect(e.message,
          "Type mismatch for property name on User, expected String but got _Smi.");
    }
    try {
      user.id = "foo";
      fail("This should throw an exception.");
    } catch (e) {
      expect(e.message,
          "Type mismatch for property id on User, expected int but got _OneByteString.");
    }
  });

  test("Accessing model object without field should return null", () {
    var user = new User();
    expect(user.name, isNull);
  });

  test("Getting/setting property that is undeclared throws exception", () {
    var user = new User();
    try {
      var x = user.foo;
      fail("Should throw exception.");
      print("$x");
    } catch (e) {
      expect(e.message, "Model type User has no property foo.");
    }
    try {
      user.foo = "hey";
      fail("Should throw exception.");
    } catch (e) {
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

    user.posts = posts;

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
    user.posts = posts;

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
    try {
      user.readMap(map);
      fail("Should throw");
    } catch (e) {
      expect(e.message, "Key bad_key does not exist for User");
    }
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
    try {
      post.readMap(postMap);
      fail("Should throw");
    } catch (e) {
      expect(e.message,
          "Expecting a Map for User in the owner field, got 12 instead.");
    }
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
    u.name =
        null; // I previously set this to a value on purpose and then reset it to null

    expect(u.name, isNull);
    expect(u.dateCreated, isNull);

    try {
      var _ = u.id;
      fail("Should throw");
    } catch (e) {
      expect(e, isNotNull);
    }
  });

  test("Primary key works", () {
    var u = new User();
    expect(u.primaryKey, "id");

    var p = new Post();
    expect(p.primaryKey, null);
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
      "dateCreated" : "1900-01-01T00:00:00Z"
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

    try {
      var _ = new TransientTest()
        ..readMap({
          "outputInt" : 3
        });
      fail("Should not get here");
    } catch (e) {
      expect(e is QueryException, true);
      expect(e.message, "Key outputInt does not exist for TransientTest");
    }
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

@proxy
@ModelBacking(UserBacking)
class User extends Object with Model implements UserBacking {

  @mappable
  String value;

  noSuchMethod(i) => super.noSuchMethod(i);
}

class UserBacking {
  @Attributes(nullable: true)
  String name;

  @Attributes(primaryKey: true)
  int id;

  DateTime dateCreated;

  List<Post> posts;
}

@proxy
@ModelBacking(PostBacking)
class Post extends Object with Model implements PostBacking {
  noSuchMethod(i) => super.noSuchMethod(i);
}

class PostBacking {
  String text;
  int id;

  User owner;
}

@proxy
@ModelBacking(TransientTestBacking)
class TransientTest extends Object with Model implements TransientTestBacking {
  @mappable
  String get defaultedText => "Mr. $text";
  void set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @mappableInput
  int inputInt;

  @mappableOutput
  int outputInt;

  noSuchMethod(i) => super.noSuchMethod(i);
}

class TransientTestBacking {
  int id;
  String text;

}
