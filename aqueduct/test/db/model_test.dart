import 'dart:convert';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'dart:mirrors';
import '../helpers.dart';

void main() {
  ManagedContext context;

  setUpAll(() {
    var ps = new DefaultPersistentStore();
    ManagedDataModel dm = new ManagedDataModel([
      TransientTest,
      TransientTypeTest,
      User,
      Post,
      PrivateField,
      EnumObject,
      TransientBelongsTo,
      TransientOwner,
      DocumentTest,
      ConstructorOverride
    ]);
    context = new ManagedContext(dm, ps);
  });

  tearDownAll(() async {
    await context.close();
  });

  test("Can set properties in constructor", () {
    final obj = new ConstructorOverride();
    expect(obj.value, "foo");
  });

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
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input value for 'name'"));
    }

    try {
      reflect(user).setField(#id, "foo");
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input value for 'id'"));
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
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Property 'foo' does not exist on 'User'"));
    }

    try {
      reflect(user).setField(#foo, "hey");
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("Property 'foo=' does not exist on 'User'"));
    }
  });

  test("Can assign and read embedded objects", () {
    var user = new User();
    user.id = 1;
    user.name = "Bob";
    List<Post> posts = <Post>[
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

    user.posts = new ManagedSet<Post>.from(posts);

    expect(user.posts.length, 3);
    expect(user.posts.first.owner, user);
    expect(user.posts.first.text, "A");

    expect(posts.first.owner, user);
    expect(posts.first.owner.name, "Bob");
  });

  test("Can assign null to relationships", () {
    var u = new User();
    u.posts = null;

    var p = new Post();
    p.owner = null;
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
    user.posts = new ManagedSet<Post>.from(posts);

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
    user.readFromMap(wash(map));

    expect(user.id, 1);
    expect(user.name, "Bob");

    var posts = postMap.map((e) => new Post()..readFromMap(wash(e))).toList();
    expect(posts[0].id, 1);
    expect(posts[1].id, 2);
    expect(posts[0].text, "hey");
    expect(posts[1].text, "ho");
  });

  test("Reading from map with bad key fails", () {
    var map = {"id": 1, "name": "Bob", "bad_key": "value"};

    var user = new User();
    try {
      user.readFromMap(wash(map));
      expect(true, false);
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input key 'bad_key'"));
    }
  });

  test("Reading from map with non-assignable type fails", () {
    try {
      new User()..readFromMap(wash({"id": "foo"}));
      expect(true, false);
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input value for 'id'"));
    }
  });

  test("Handles DateTime conversion", () {
    var dateString = "2000-01-01T05:05:05.010Z";
    var map = {"id": 1, "name": "Bob", "dateCreated": dateString};
    var user = new User();
    user.readFromMap(wash(map));

    expect(user.dateCreated.difference(DateTime.parse(dateString)), Duration.zero);

    var remap = user.asMap();
    expect(remap["dateCreated"], dateString);

    map = {"id": 1, "name": "Bob", "dateCreated": 123};
    user = new User();
    try {
      user.readFromMap(wash(map));
      expect(true, false);
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input value for 'dateCreated'"));
    }
  });

  test("Handles input of type num for double precision float properties of the model", () {
    var m = new TransientTypeTest()
      ..readFromMap(wash({
        "transientDouble": 30,
      }));

    expect(m.transientDouble, 30.0);
  });

  test("Reads embedded object", () {
    var postMap = {
      "text": "hey",
      "id": 1,
      "owner": {"name": "Alex", "id": 18}
    };

    var post = new Post()..readFromMap(wash(postMap));
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
      post.readFromMap(wash(postMap));
      successful = true;
    } on ValidationException catch (e) {
      expectError(e, contains("invalid input type for 'owner'"));
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
    t.readFromMap(wash({"inOut": 2}));
    expect(t.inOut, 2);
    expect(t["inOut"], isNull);
  });

  test("mappableInput properties are read in readMap", () {
    var t = new TransientTest()..readFromMap(wash({"id": 1, "defaultedText": "bar foo"}));
    expect(t.id, 1);
    expect(t.text, "foo");
    expect(t.inputInt, isNull);
    expect(t.inOut, isNull);

    t = new TransientTest()..readFromMap(wash({"inputOnly": "foo"}));
    expect(t.text, "foo");

    t = new TransientTest()..readFromMap(wash({"inputInt": 2}));
    expect(t.inputInt, 2);

    t = new TransientTest()..readFromMap(wash({"inOut": 2}));
    expect(t.inOut, 2);

    t = new TransientTest()..readFromMap(wash({"bothOverQualified": "foo"}));
    expect(t.text, "foo");
  });

  test("mappableOutput properties are emitted in asMap", () {
    var t = new TransientTest()..text = "foo";

    expect(t.asMap()["defaultedText"], "Mr. foo");
    expect(t.asMap()["outputOnly"], "foo");
    expect(t.asMap()["bothButOnlyOnOne"], "foo");
    expect(t.asMap()["bothOverQualified"], "foo");

    t = new TransientTest()..outputInt = 2;
    expect(t.asMap()["outputInt"], 2);

    t = new TransientTest()..inOut = 2;
    expect(t.asMap()["inOut"], 2);
  });

  test("Transient properties are type checked in readMap", () {
    try {
      new TransientTest()..readFromMap(wash({"id": 1, "defaultedText": 2}));

      throw 'Unreachable';
    } on ValidationException {}

    try {
      new TransientTest()..readFromMap(wash({"id": 1, "inputInt": "foo"}));

      throw 'Unreachable';
    } on ValidationException {}
  });

  test("Properties that aren't mappableInput are not read in readMap", () {
    try {
      new TransientTest()..readFromMap(wash({"outputOnly": "foo"}));
      throw 'Unreachable';
    } on ValidationException {}

    try {
      new TransientTest()..readFromMap(wash({"invalidOutput": "foo"}));
      throw 'Unreachable';
    } on ValidationException {}

    try {
      new TransientTest()..readFromMap(wash({"invalidInput": "foo"}));
      throw 'Unreachable';
    } on ValidationException {}

    try {
      new TransientTest()..readFromMap(wash({"bothButOnlyOnOne": "foo"}));
      throw 'Unreachable';
    } on ValidationException {}

    try {
      new TransientTest()..readFromMap(wash({"outputInt": "foo"}));
      throw 'Unreachable';
    } on ValidationException {}
  });

  test("mappableOutput properties that are null are not emitted in asMap", () {
    var m = (new TransientTest()
          ..id = 1
          ..text = null)
        .asMap();

    expect(m.length, 3);
    expect(m["id"], 1);
    expect(m["text"], null);
    expect(m["defaultedText"], "Mr. null");
  });

  test("Properties that aren't mappableOutput are not emitted in asMap", () {
    var m = (new TransientTest()
          ..id = 1
          ..text = "foo"
          ..inputInt = 2)
        .asMap();

    expect(m.length, 6);
    expect(m["id"], 1);
    expect(m["text"], "foo");
    expect(m["defaultedText"], "Mr. foo");
    expect(m["outputOnly"], "foo");
    expect(m["bothButOnlyOnOne"], "foo");
    expect(m["bothOverQualified"], "foo");
  });

  test("Transient Properties of all types can be read and returned", () {
    var dateString = "2016-10-31T15:40:45+00:00";
    var m = (new TransientTypeTest()
          ..readFromMap(wash({
            "transientInt": 5,
            "transientBigInt": 123456789,
            "transientString": "lowercase string",
            "transientDate": dateString,
            "transientBool": true,
            "transientDouble": 30.5,
            "transientMap": {"key": "value", "anotherKey": "anotherValue"},
            "transientList": [1, 2, 3, 4, 5],
            "defaultList": [1, "foo"],
            "defaultMap": {"key": "value"},
            "deepList": [
              {"str": "val"},
              {"other": "otherval"}
            ],
            "deepMap": {
              "ok": {"ik1": 1, "ik2": 2}
            }
          })))
        .asMap();

    expect(m["transientInt"], 5);
    expect(m["transientBigInt"], 123456789);
    expect(m["transientString"], "lowercase string");
    expect(m["transientDate"].difference(DateTime.parse(dateString)), Duration.zero);
    expect(m["transientBool"], true);
    expect(m["transientDouble"], 30.5);
    expect(m["transientList"], [1, 2, 3, 4, 5]);
    expect(m["defaultMap"], {"key": "value"});
    expect(m["defaultList"], [1, "foo"]);
    expect(m["deepList"], [
      {"str": "val"},
      {"other": "otherval"}
    ]);
    expect(m["deepMap"], {
      "ok": {"ik1": 1, "ik2": 2}
    });

    var tm = m["transientMap"];
    expect(tm is Map, true);
    expect(tm["key"], "value");
    expect(tm["anotherKey"], "anotherValue");
  });

  test("If primitive type cannot be parsed into correct type, it fails with validation exception", () {
    try {
      new TransientTypeTest()
        ..readFromMap({
          "transientInt": "a string"
        });
      fail('unreachable');
    } on ValidationException {}
  });

  test("If complex type cannot be parsed into exact type, it fails with validation exception", () {
    try {
      new TransientTypeTest()
        ..readFromMap({
          "deepList": wash([
            {"str": 1}
          ])
        });
      fail('unreachable');
    } on ValidationException {}

    try {
      new TransientTypeTest()
        ..readFromMap({
          "deepList": wash([
            {"str": "val"},
            {"int": 2}
          ])
        });
      fail('unreachable');
    } on ValidationException {}

    try {
      new TransientTypeTest()
        ..readFromMap({
          "deepList": wash(["str"])
        });
      fail('unreachable');
    } on ValidationException {}

    try {
      new TransientTypeTest()
        ..readFromMap({
          "deepMap": wash({"str": 1})
        });
      fail('unreachable');
    } on ValidationException {}

    try {
      new TransientTypeTest()
        ..readFromMap({
          "deepMap": wash({
            "key": {"str": "val", "int": 2}
          })
        });
      fail('unreachable');
    } on ValidationException {}

    try {
      new TransientTypeTest()..readFromMap({"deepMap": wash("str")});
      fail('unreachable');
    } on ValidationException {}
  });

  test("Reading hasMany relationship from JSON succeeds", () {
    var u = new User();
    u.readFromMap(wash({
      "name": "Bob",
      "id": 1,
      "posts": [
        {"text": "Hi", "id": 1}
      ]
    }));
    expect(u.posts.length, 1);
    expect(u.posts[0].id, 1);
    expect(u.posts[0].text, "Hi");
  });

  test("Reading/writing instance property that isn't marked as transient shows up nowhere", () {
    var t = new TransientTest();
    try {
      t.readFromMap(wash({"notAnAttribute": true}));
      expect(true, false);
    } on ValidationException {}

    t.notAnAttribute = "foo";
    expect(t.asMap().containsKey("notAnAttribute"), false);
  });

  test("Omit transient properties in asMap when object is a foreign key reference", () {
    var b = new TransientBelongsTo()
      ..id = 1
      ..owner = (new TransientOwner()..id = 1);
    expect(b.asMap(), {
      "id": 1,
      "owner": {"id": 1}
    });
  });

  group("Persistent enum fields", () {
    test("Can assign/read enum value to persistent property", () {
      var e = new EnumObject();
      e.enumValues = EnumValues.abcd;
      expect(e.enumValues, EnumValues.abcd);
    });

    test("Enum value in readMap is a matching string", () {
      var e = new EnumObject()..readFromMap(wash({"enumValues": "efgh"}));
      expect(e.enumValues, EnumValues.efgh);
    });

    test("Enum value in asMap is a matching string", () {
      var e = new EnumObject()..enumValues = EnumValues.other18;
      expect(e.asMap()["enumValues"], "other18");
    });

    test("Cannot assign value via backingMap or readMap that isn't a valid enum case", () {
      var e = new EnumObject();
      try {
        e.readFromMap(wash({"enumValues": "foobar"}));
        expect(true, false);
      } on ValidationException catch (e) {
        expectError(e, contains("invalid option for key 'enumValues'"));
      }

      try {
        e["enumValues"] = "foobar";
        expect(true, false);
      } on ValidationException catch (e) {
        expectError(e, contains("invalid input value for 'enumValues'"));
      }
    });
  });

  group("Private fields", () {
    test("Private fields on entity", () {
      var entity = context.dataModel.entityForType(PrivateField);
      expect(entity.attributes["_private"], isNotNull);
    });

    test("Can get/set value of private field", () {
      var p = new PrivateField();
      p._private = "x";
      expect(p._private, "x");
    });

    test("Can get/set value of private field thru public accessor", () {
      var p = new PrivateField()..public = "x";
      expect(p.public, "x");
      expect(p._private, "x");
    });

    test("Private fields are omitted from asMap()", () {
      var p = new PrivateField()..public = "x";
      expect(p.asMap(), {"public": "x"});

      p = new PrivateField().._private = "x";
      expect(p.asMap(), {"public": "x"});
    });

    test("Private fields cannot be set in readFromMap()", () {
      var p = new PrivateField();
      p.readFromMap(wash({"_private": "x"}));
      expect(p.public, isNull);
      expect(p._private, isNull);
    });
  });

  group("Document data type", () {
    test("Can read object into document data type from map", () {
      final o = new DocumentTest();
      o.readFromMap(wash({
        "document": {"key": "value"}
      }));

      expect(o.document.data, {"key": "value"});
    });

    test("Can read array into document data type from list", () {
      final o = new DocumentTest();
      o.readFromMap(wash({
        "document": [
          {"key": "value"},
          1
        ]
      }));

      expect(o.document.data, [
        {"key": "value"},
        1
      ]);
    });

    test("Can emit object into map from object document data type", () {
      final o = new DocumentTest()..document = new Document({"key": "value"});
      expect(o.asMap(), {
        "document": {"key": "value"}
      });
    });

    test("Can emit array into map from array document data type", () {
      final o = new DocumentTest()
        ..document = new Document([
          {"key": "value"},
          1
        ]);
      expect(o.asMap(), {
        "document": [
          {"key": "value"},
          1
        ]
      });
    });
  });
}

class User extends ManagedObject<_User> implements _User {
  @Serialize()
  String value;
}

class _User {
  @Column(nullable: true)
  String name;

  @Column(primaryKey: true)
  int id;

  DateTime dateCreated;

  ManagedSet<Post> posts;
}

class Post extends ManagedObject<_Post> implements _Post {}

class _Post {
  @primaryKey
  int id;

  String text;

  @Relate(Symbol('posts'))
  User owner;
}

class TransientTest extends ManagedObject<_TransientTest> implements _TransientTest {
  String notAnAttribute;

  @Serialize(input: false, output: true)
  String get defaultedText => "Mr. $text";

  @Serialize(input: true, output: false)
  set defaultedText(String str) {
    text = str.split(" ").last;
  }

  @Serialize(input: true, output: false)
  set inputOnly(String s) {
    text = s;
  }

  @Serialize(input: false, output: true)
  String get outputOnly => text;

  set outputOnly(String s) {
    text = s;
  }

  // This is intentionally invalid
  @Serialize(input: true, output: false)
  String get invalidInput => text;

  // This is intentionally invalid
  @Serialize(input: false, output: true)
  set invalidOutput(String s) {
    text = s;
  }

  @Serialize()
  String get bothButOnlyOnOne => text;

  set bothButOnlyOnOne(String s) {
    text = s;
  }

  @Serialize(input: true, output: false)
  int inputInt;

  @Serialize(input: false, output: true)
  int outputInt;

  @Serialize()
  int inOut;

  @Serialize()
  String get bothOverQualified => text;

  @Serialize()
  set bothOverQualified(String s) {
    text = s;
  }
}

class _TransientTest {
  @primaryKey
  int id;

  String text;
}

class TransientTypeTest extends ManagedObject<_TransientTypeTest> implements _TransientTypeTest {
  @Serialize(input: false, output: true)
  int get transientInt => backingInt + 1;

  @Serialize(input: true, output: false)
  set transientInt(int i) {
    backingInt = i - 1;
  }

  @Serialize(input: false, output: true)
  int get transientBigInt => backingBigInt ~/ 2;

  @Serialize(input: true, output: false)
  set transientBigInt(int i) {
    backingBigInt = i * 2;
  }

  @Serialize(input: false, output: true)
  String get transientString => backingString.toLowerCase();

  @Serialize(input: true, output: false)
  set transientString(String s) {
    backingString = s.toUpperCase();
  }

  @Serialize(input: false, output: true)
  DateTime get transientDate => backingDateTime.add(new Duration(days: 1));

  @Serialize(input: true, output: false)
  set transientDate(DateTime d) {
    backingDateTime = d.subtract(new Duration(days: 1));
  }

  @Serialize(input: false, output: true)
  bool get transientBool => !backingBool;

  @Serialize(input: true, output: false)
  set transientBool(bool b) {
    backingBool = !b;
  }

  @Serialize(input: false, output: true)
  double get transientDouble => backingDouble / 5;

  @Serialize(input: true, output: false)
  set transientDouble(double d) {
    backingDouble = d * 5;
  }

  @Serialize(input: false, output: true)
  Map<String, String> get transientMap {
    List<String> pairs = backingMapString.split(",");

    var returnMap = new Map<String, String>();

    pairs.forEach((String pair) {
      List<String> pairList = pair.split(":");
      returnMap[pairList[0]] = pairList[1];
    });

    return returnMap;
  }

  @Serialize(input: true, output: false)
  set transientMap(Map<String, String> m) {
    var pairStrings = m.keys.map((key) {
      String value = m[key];
      return "$key:$value";
    });

    backingMapString = pairStrings.join(",");
  }

  @Serialize(input: false, output: true)
  List<int> get transientList {
    return backingListString.split(",").map((s) => int.parse(s)).toList();
  }

  @Serialize(input: true, output: false)
  set transientList(List<int> l) {
    backingListString = l.map((i) => i.toString()).join(",");
  }

  @Serialize()
  List<Map<String, String>> deepList;

  @Serialize()
  Map<String, Map<String, int>> deepMap;

  @Serialize()
  Map<String, dynamic> defaultMap;

  @Serialize()
  List<dynamic> defaultList;
}

class _TransientTypeTest {
  // All of the types - ManagedPropertyType
  @primaryKey
  int id;

  int backingInt;

  @Column(databaseType: ManagedPropertyType.bigInteger)
  int backingBigInt;

  String backingString;

  DateTime backingDateTime;

  bool backingBool;

  double backingDouble;

  String backingMapString;

  String backingListString;
}

class PrivateField extends ManagedObject<_PrivateField> implements _PrivateField {
  @Serialize(input: true, output: false)
  set public(String p) {
    _private = p;
  }

  @Serialize(input: false, output: true)
  String get public => _private;
}

class _PrivateField {
  @primaryKey
  int id;

  String _private;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}

class _EnumObject {
  @primaryKey
  int id;

  EnumValues enumValues;
}

enum EnumValues { abcd, efgh, other18 }

class TransientOwner extends ManagedObject<_TransientOwner> implements _TransientOwner {
  @Serialize(input: false, output: true)
  int v = 2;
}

class _TransientOwner {
  @primaryKey
  int id;

  TransientBelongsTo t;
}

class TransientBelongsTo extends ManagedObject<_TransientBelongsTo> implements _TransientBelongsTo {}

class _TransientBelongsTo {
  @primaryKey
  int id;

  @Relate(Symbol('t'))
  TransientOwner owner;
}

void expectError(ValidationException exception, Matcher matcher) {
  expect(exception.toString(), matcher);
}

class DocumentTest extends ManagedObject<_DocumentTest> implements _DocumentTest {}

class _DocumentTest {
  @primaryKey
  int id;

  Document document;
}

class ConstructorOverride extends ManagedObject<_ConstructorOverride> implements _ConstructorOverride {
  ConstructorOverride() {
    value = "foo";
  }
}

class _ConstructorOverride {
  @primaryKey
  int id;

  String value;
}

T wash<T>(dynamic data) {
  return json.decode(json.encode(data)) as T;
}
