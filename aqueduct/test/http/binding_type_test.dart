import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import "package:test/test.dart";

void main() {
  group("Non-list success", () {
    test("Can bind String to query, header, path", () {
      final controller = StandardSet();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind parseable types to query, header, path", () {
      final controller = ParseSet();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind bool to query", () {
      final controller = BoolBind();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind Serializable to body", () {
      final controller = BodyBind();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });
  });

  group("List success", () {
    test("Can bind String to query, header, path", () {
      final controller = StandardListSet();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind parseable types to query, header, path", () {
      final controller = ParseListSet();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind bool to query", () {
      final controller = BoolListBind();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind Serializable to body", () {
      final controller = BodyListBind();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

    test("Can bind Serializable to body with filters", () {
      final controller = BodyListBindWithFilters();
      controller.restore(controller.recycledState);
      controller.didAddToChannel();
      // Just expecting that we don't throw
      expect(true, true);
    });

  });
}

class StandardSet extends ResourceController {
  @Operation.get('id')
  Future<Response> get1(@Bind.header("foo") String a, @Bind.path("id") String b,
      @Bind.query("c") String c) async {
    return Response.ok(null);
  }
}

class ParseSet extends ResourceController {
  @Operation.get('id')
  Future<Response> get1(@Bind.header("foo") int a, @Bind.path("id") DateTime b,
      @Bind.query("c") num c) async {
    return Response.ok(null);
  }
}

class BoolBind extends ResourceController {
  @Operation.get('id')
  // ignore: avoid_positional_boolean_parameters
  Future<Response> get1(@Bind.query("foo") bool a) async {
    return Response.ok(null);
  }
}

class BodyBind extends ResourceController {
  @Operation.post()
  Future<Response> get1(@Bind.body() Serial a) async {
    return Response.ok(null);
  }
}

class StandardListSet extends ResourceController {
  Future<Response> get1(@Bind.header("foo") List<String> a,
      @Bind.header("id") List<String> b, @Bind.query("c") List<String> c) async {
    return Response.ok(null);
  }
}

class ParseListSet extends ResourceController {
  Future<Response> get1(@Bind.header("foo") List<int> a,
      @Bind.header("id") List<DateTime> b, @Bind.query("c") List<num> c) async {
    return Response.ok(null);
  }
}

class BoolListBind extends ResourceController {
  @Operation.get('id')
  Future<Response> get1(@Bind.query("foo") List<bool> a) async {
    return Response.ok(null);
  }
}

class BodyListBind extends ResourceController {
  @Operation.post()
  Future<Response> get1(@Bind.body() List<Serial> a) async {
    return Response.ok(null);
  }
}

class BodyListBindWithFilters extends ResourceController {
  @Operation.post()
  Future<Response> get1(@Bind.body(ignore: ["id"]) List<Serial> a) async {
    return Response.ok(null);
  }
}

class Serial extends Serializable {
  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return {};
  }
}
