import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/mixin.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  Controller.letUncaughtExceptionsEscape = true;
  ManagedContext context;
  HttpServer server;

  setUpAll(() async {
    context = await contextWithModels([TestModel, StringModel]);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8888);
    var router = Router();
    router.route("/users/[:id]").link(() => TestModelController(context));
    router.route("/string/:id").link(() => StringController(context));
    router.didAddToChannel();

    server.listen((req) async {
      // ignore: unawaited_futures
      router.receive(Request(req));
    });
  });

  tearDownAll(() async {
    await context.close();
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
        body: json.encode({"name": "joe"}));
    expect(response.statusCode, 200);
  });

  test("Request without path parameter and body", () async {
    var response = await http.post("http://localhost:8888/users",
        headers: {"Content-Type": "application/json;charset=utf-8"},
        body: json.encode({"name": "joe"}));
    expect(response.statusCode, 200);
  });

  test("Non-integer, oddly named identifier", () async {
    var response = await http.get("http://localhost:8888/string/bar");
    expect(response.body, '"bar"');
  });
}

class TestModelController extends QueryController<TestModel> {
  TestModelController(ManagedContext context) : super(context);

  @Operation.get()
  Future<Response> getAll() async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    if (query.values.backing.contents.isNotEmpty) {
      statusCode = 400;
    }

    return Response(statusCode, {}, null);
  }

  @Operation.get("id")
  Future<Response> getOne(@Bind.path("id") int id) async {
    int statusCode = 200;

    if (query == null) {
      statusCode = 400;
    }

    final comparisonMatcher = (query as QueryMixin)
        .expressions
        .firstWhere((expr) => expr.keyPath.path.first.name == "id")
        .expression as ComparisonExpression;
    if (comparisonMatcher.operator != PredicateOperator.equalTo ||
        comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values.backing.contents.isNotEmpty) {
      statusCode = 400;
    }

    return Response(statusCode, {}, null);
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

    final comparisonMatcher = (query as QueryMixin)
        .expressions
        .firstWhere((expr) => expr.keyPath.path.first.name == "id")
        .expression as ComparisonExpression;
    if (comparisonMatcher.operator != PredicateOperator.equalTo ||
        comparisonMatcher.value != id) {
      statusCode = 400;
    }

    if (query.values == null) {
      statusCode = 400;
    }

    if (query.values.name != "joe") {
      statusCode = 400;
    }

    return Response(statusCode, {}, null);
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

    return Response(statusCode, {}, null);
  }

  @Operation.post("id")
  Future<Response> crash(@Bind.path("id") int id) async {
    return Response.ok("");
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
  StringController(ManagedContext context) : super(context);

  @Operation.get("id")
  Future<Response> get(@Bind.path("id") String id) async {
    final comparisonMatcher = (query as QueryMixin)
        .expressions
        .firstWhere((expr) => expr.keyPath.path.first.name == "foo")
        .expression as StringExpression;
    return Response.ok(comparisonMatcher.value);
  }
}

class StringModel extends ManagedObject<_StringModel> implements _StringModel {}

class _StringModel {
  @Column(primaryKey: true)
  String foo;
}
