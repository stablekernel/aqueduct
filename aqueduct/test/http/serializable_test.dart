import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  final object = TestSerializable();

  test("not specified", () {
    object.read({"key": "value"});
    expect(object.contents, {"key": "value"});
  });

  group("required", () {
    test("empty", () {
      object.read({}, require: []);
      expect(object.contents, {});
    });

    test("input violation", () {
      try {
        object.read({}, require: ["key"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }

      try {
        object.read({"key": ""}, require: ["key", "missing"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }
    });

    test("valid input", () {
      object.read({"key": ""}, require: ["key"]);
      expect(object.contents, {"key": ""});

      object.read({"key": "", "next": ""}, require: ["key", "next"]);
      expect(object.contents, {"key": "", "next": ""});
    });
  });

  group("ignore", () {
    test("empty", () {
      object.read({}, ignore: []);
      expect(object.contents, {});
    });

    test("input violation", () {
      object.read({"key": ""}, ignore: ["key"]);
      expect(object.contents, {});

      object.read({"1": "", "2": "", "3": ""}, ignore: ["1", "2"]);
      expect(object.contents, {"3": ""});
    });

    test("valid input", () {
      object.read({"1": "", "2": ""}, ignore: ["not1or2"]);
      expect(object.contents, {"1": "", "2": ""});
    });
  });

  group("error", () {
    test("empty", () {
      object.read({"1": ""}, reject: []);
      expect(object.contents, {"1": ""});
    });

    test("input violation", () {
      try {
        object.read({"key": ""}, reject: ["key"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }

      try {
        object.read({"key": ""}, reject: ["key", "missing"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }
    });

    test("valid input", () {
      object.read({"key": ""}, reject: ["not-key"]);
      expect(object.contents, {"key": ""});

      object.read({"key": "", "next": ""}, reject: ["not-key", "not-next"]);
      expect(object.contents, {"key": "", "next": ""});
    });
  });

  group("accept", () {
    test("empty", () {
      object.read({}, accept: []);
      expect(object.contents, {});
    });

    test("input violation", () {
      object.read({"notKey": ""}, accept: ["key"]);
      expect(object.contents, {});

      object.read({"1": "", "2": "", "3": ""}, accept: ["1", "2"]);
      expect(object.contents, {"1": "", "2": ""});
    });

    test("valid input", () {
      object.read({"1": "", "2": ""}, accept: ["1", "2"]);
      expect(object.contents, {"1": "", "2": ""});

      object.read({"1": "", "2": ""}, accept: ["1", "2", "3"]);
      expect(object.contents, {"1": "", "2": ""});
    });
  });

  test("ignore + error conflict is resolved to error", () {
    try {
      object.read({"key": ""}, ignore: ["key"], reject: ["key"]);
      fail('unreachable');
    } on SerializableException catch (e) {
      expect(e.response.statusCode, 400);
    }
  });

  test("accept + error conflict is resolved to error", () {
    try {
      object.read({"key": ""}, accept: [], reject: ["key"]);
      fail('unreachable');
    } on SerializableException catch (e) {
      expect(e.response.statusCode, 400);
    }
  });

  test("accept + ignore", () {
    object.read({"key": ""}, accept: ["key"], ignore: ["key"]);
    expect(object.contents, {});

    object.read({"1": "", "2": ""}, accept: ["1"], ignore: []);
    expect(object.contents, {"1": ""});
  });
}

class TestSerializable extends Serializable {
  Map<String, dynamic> contents;

  @override
  void readFromMap(Map<String, dynamic> object) {
    contents = object;
  }

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}
