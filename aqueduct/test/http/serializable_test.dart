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
      object.read({}, required: []);
      expect(object.contents, {});
    });

    test("input violation", () {
      try {
        object.read({}, required: ["key"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }

      try {
        object.read({"key": ""}, required: ["key", "missing"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }
    });

    test("valid input", () {
      object.read({"key": ""}, required: ["key"]);
      expect(object.contents, {"key": ""});

      object.read({"key": "", "next": ""}, required: ["key", "next"]);
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
      object.read({"1": ""}, error: []);
      expect(object.contents, {"1": ""});
    });

    test("input violation", () {
      try {
        object.read({"key": ""}, error: ["key"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }

      try {
        object.read({"key": ""}, error: ["key", "missing"]);
        fail('unreachable');
      } on SerializableException catch (e) {
        expect(e.response.statusCode, 400);
      }
    });

    test("valid input", () {
      object.read({"key": ""}, error: ["not-key"]);
      expect(object.contents, {"key": ""});

      object.read({"key": "", "next": ""}, error: ["not-key", "not-next"]);
      expect(object.contents, {"key": "", "next": ""});
    });
  });
  
  test("ignore + error conflict is resolved to error", () {
    try {
      object.read({"key": ""}, ignore: ["key"], error: ["key"]);
      fail('unreachable');
    } on SerializableException catch (e) {
      expect(e.response.statusCode, 400);
    }
  });
}

class TestSerializable extends Serializable {
  Map<String, dynamic> contents;

  @override
  void readFromMap(Map<String, dynamic> object)
  {
    contents = object;
  }

  @override
  Map<String, dynamic> asMap()
  {
    return null;
  }
}