import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../helpers.dart';


void main() {
  Controller.letUncaughtExceptionsEscape = true;
  ManagedContext context;
  HttpServer server;

  setUpAll(() async {
    context = await contextWithModels([TestModel, StringModel]);
    ManagedContext.defaultContext = context;

    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 8888);
    var router = new Router();
    router.route("/users/[:id]").generate(() => new TestModelController());
    router.route("/string/:id").generate(() => new StringController());
    router.prepare();

    server.listen((req) async {
      router.receive(new Request(req));
    });
  });

  tearDownAll(() async {
    await context.persistentStore.close();
    await server?.close(force: true);
  });

  test("Request with no path parameters OK", () async {
    var response = await http.get("http://localhost:8888/users");
    expect(response.statusCode, 200);
  });

  test("Request with path parameter of type needing parse OK", () async {
    var response = await http.get("http://localhost:8888/users/1");
    expect(response.statusCode, 200);
  });

  test("Request with path parameter of wrong type returns 404", () async {
    var response = await http.get("http://localhost:8888/users/foo");
    expect(response.statusCode, 404);
  });

  test("Request with path parameter and body", () async {
    var response = await http.put("http://localhost:8888/users/2",
        headers: {"Content-Type": "application/json;charset=utf-8"},
        body: JSON.encode({"name": "joe"}));
    expect(response.statusCode, 200);
  });

  test("Request without path parameter and body", () async {
    var response = await http.post("http://localhost:8888/users",
        headers: {"Content-Type": "application/json;charset=utf-8"},
        body: JSON.encode({"name": "joe"}));
    expect(response.statusCode, 200);
  });

  test("Non-integer, oddly named identifier", () async {
    var response = await http.get("http://localhost:8888/string/bar");
    expect(response.body, '"bar"');
  });
}

class TestModelController extends QueryController<TestModel> {
  @Operation.get()
  Future<Response> getAll() async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    if (query.values.backingMap.length != 0) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @Operation.get("id")
  Future<Response> getOne(@Bind.path("id") int id) async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    ComparisonMatcherExpression comparisonMatcher = query.where["id"];
    if (comparisonMatcher.operator != MatcherOperator.equalTo ||
        comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values.backingMap.length != 0) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @Operation.put("id")
  Future<Response> putOne(@Bind.path("id") int id) async {
    int statusCode = 200;

    if (query.values == null) {
      statusCode = 400;
    }
    if (query.values.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    ComparisonMatcherExpression comparisonMatcher = query.where["id"];
    if (comparisonMatcher.operator != MatcherOperator.equalTo ||
        comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values == null) {
      statusCode = 400;
    }

    if (query.values.name != "joe") {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @Operation.post()
  Future<Response> create() async {
    int statusCode = 200;
    if (query.values == null) {
      statusCode = 400;
    }
    if (query.values.name != "joe") {
      statusCode = 400;
    }
    if (query == null) {
      statusCode = 400;
    }

    return new Response(statusCode, {}, null);
  }

  @Operation.post("id")
  Future<Response> crash(@Bind.path("id") int id) async {
    return new Response.ok("");
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @Column(primaryKey: true)
  int id;

  String name;
  String email;
}

class StringController extends QueryController<StringModel> {
  @Operation.get("id")
  Future<Response> get(@Bind.path("id") String id) async {
    StringMatcherExpression comparisonMatcher = query.where["foo"];
    return new Response.ok(comparisonMatcher.value);
  }
}

class StringModel extends ManagedObject<_StringModel> implements _StringModel {}
class _StringModel {
  @Column(primaryKey: true)
  String foo;
}