import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

void main() {
  ServerRoot server;

  setUp(() async {
    DefaultRecyclable.stateCount = 0;
    MiddlewareRecyclable.stateCount = 0;

    server = ServerRoot();
    await server.open();
  });

  tearDown(() async {
    await server.close();
  });

  test("A controller that does not implement Recyclable is reused", () async {
    server.root.link(() => DefaultController());
    server.root.didAddToChannel();

    final r1 = await http.get("http://localhost:4040");
    final r2 = await http.get("http://localhost:4040");

    final firstAddress = json.decode(r1.body)["hashCode"];
    final secondAddress = json.decode(r2.body)["hashCode"];
    expect(firstAddress, equals(secondAddress));
  });

  test("A controller that implements Recyclable creates a new instance for each request", () async {
    server.root.link(() => DefaultRecyclable());
    server.root.didAddToChannel();

    final r1 = await http.get("http://localhost:4040");
    final r2 = await http.get("http://localhost:4040");

    final firstAddress = json.decode(r1.body)["hashCode"];
    final secondAddress = json.decode(r2.body)["hashCode"];
    expect(firstAddress, isNot(secondAddress));
  });

  test("Receiving simultaneous request will always use a new Recyclable instance", () async {
    server.root.link(() => DefaultRecyclable());
    server.root.didAddToChannel();

    final addresses = await Future.wait([
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["hashCode"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["hashCode"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["hashCode"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["hashCode"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["hashCode"]),
    ]);

    expect(addresses.every((addr) => addresses.where((testAddr) => addr == testAddr).length == 1), true);
  });

  test("A Recyclable instance reuses recycleState", () async {
    server.root.link(() => DefaultRecyclable());
    server.root.didAddToChannel();

    final states = await Future.wait([
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
    ]);

    expect(states.every((state) => state == "state"), true);
  });

  test("recycleState is only called once", () async {
    server.root.link(() => DefaultRecyclable());
    server.root.didAddToChannel();

    await Future.wait([
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
      http.get("http://localhost:4040").then((r) => json.decode(r.body)["state"]),
    ]);

    expect(DefaultRecyclable.stateCount, 1);
  });

  test("A controller that is not Recyclable, but declares non-final properties throws a runtime error", () {
    try {
      server.root.link(() => MutablePropertyController());
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("MutablePropertyController"));
    }
  });

  test("A controller that is not Recyclable, but declares a setter throws a runtime error", () {
    try {
      server.root.link(() => MutableSetterController());
      fail('unreachable');
    } on ArgumentError catch (e) {
      expect(e.toString(), contains("MutableSetterController"));
    }
  });

  test("A recycled controller always sends unhandled requests to the next linked controller", () async {
    server.root.link(() => MiddlewareRecyclable()).link(() => DefaultController());
    server.root.didAddToChannel();

    final List<Map<String, dynamic>> responses = await Future.wait([
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
    ]);

    expect(responses.every((b) => responses.every((ib) => ib["hashCode"] == b["hashCode"])), true);
    expect(responses.every((b) => b["middleware-state"] == "state"), true);
    expect(responses.every((b) => responses.where((ib) => ib["middleware-address"] == b["middleware-address"]).length == 1), true);

    expect(MiddlewareRecyclable.stateCount, 1);
  });

  test("A recycled controller sends unhandled request to the next linked recyclable", () async {
    server.root.link(() => MiddlewareRecyclable()).link(() => DefaultRecyclable());
    server.root.didAddToChannel();

    final List<Map<String, dynamic>> responses = await Future.wait([
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
      http.get("http://localhost:4040").then((r) => json.decode(r.body) as Map<String, dynamic>),
    ]);

    expect(responses.every((b) => responses.where((ib) => ib["hashCode"] == b["hashCode"]).length == 1), true);
    expect(responses.every((b) => b["state"] == "state"), true);
    expect(responses.every((b) => b["middleware-state"] == "state"), true);
    expect(responses.every((b) => responses.where((ib) => ib["middleware-address"] == b["middleware-address"]).length == 1), true);

    expect(DefaultRecyclable.stateCount, 1);
    expect(MiddlewareRecyclable.stateCount, 1);
  });
}

class ServerRoot {
  ServerRoot();

  HttpServer server;
  Controller root = Controller((req) => req);

  Future open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 4040);
    server.map((httpReq) => new Request(httpReq)).listen(root.receive);
  }

  Future close() {
    return server.close();
  }
}

class DefaultController extends Controller {
  @override
  FutureOr<RequestOrResponse> handle(Request req) {
    return new Response.ok(<String, dynamic>{"hashCode": this.hashCode});
  }
}

class DefaultRecyclable extends Controller implements Recyclable<String> {
  static int stateCount;
  String state;

  @override
  FutureOr<RequestOrResponse> handle(Request req) {
    return new Response.ok({"hashCode": this.hashCode, "state": state});
  }

  @override
  void restore(String state) {
    this.state = state;
  }

  @override
  String get recycledState {
    stateCount ++;
    return "state";
  }
}

class MutablePropertyController extends Controller {
  String mutableProperty;
}

class MutableSetterController extends Controller {
  set mutableSetter(String s) {}
}

class MiddlewareRecyclable extends Controller implements Recyclable<String> {
  static int stateCount;
  String state;

  @override
  FutureOr<RequestOrResponse> handle(Request req) {
    req.addResponseModifier((r) {
      r.body["middleware-state"] = state;
      r.body["middleware-address"] = "$hashCode";
    });

    return req;
  }

  @override
  void restore(String state) {
    this.state = state;
  }

  @override
  String get recycledState {
    stateCount ++;
    return "state";
  }

}