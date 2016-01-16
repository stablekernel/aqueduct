import 'package:test/test.dart';
import 'dart:io';
import 'package:monadart/monadart.dart';
import 'dart:convert';
import '../helpers.dart';
import 'package:postgresql/postgresql.dart';

void main() {
  QueryAdapter adapter;
  HttpServer server;
  TestClient client = new TestClient(8080)
    ..clientID = "com.stablekernel.app1"
    ..clientSecret = "kilimanjaro";

  tearDownAll(() async {
    await server.close();
  });

  setUp(() async {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await connect(uri);
    });

    var authenticationServer = new AuthenticationServer<TestUser, Token>(
        new AuthDelegate<TestUser, Token>(adapter));

    HttpServer
        .bind("localhost", 8080,
          v6Only: false, shared: false)
          .then((s)
    {
      server = s;
      //new Logger("monadart").onRecord.listen((rec) => print("${rec}"));

      server.listen((req) {
        var resReq = new ResourceRequest(req);
        var authController = new AuthController<TestUser, Token>(authenticationServer);
        authController.deliver(resReq);
      });
    });

    await generateTemporarySchemaFromModels(adapter, [TestUser, Token]);
  });

  tearDown(() {
    server.close(force: true);
    adapter.close();
    adapter = null;
  });

  test("POST token responds with token on correct input", () async {
    await createUsers(adapter, 1);

    var req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    var res = await req.post();

    expect(res, hasResponse(200, [], matchesJSON({
      "access_token" : hasLength(greaterThan(0)),
      "refresh_token" : hasLength(greaterThan(0)),
      "expires_in" : greaterThan(3500),
      "token_type" : "bearer"
    })));
  });

  test("POST token header failure cases", () async {
    await createUsers(adapter, 1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};

    var req = client.request("/auth/token")
      ..formData = m;
    expect(await req.post(), hasStatus(401), reason: "omit authorization header");

    req = client.request("/auth/token")
      ..headers = {"Authorization" : "foobar"}
      ..formData = m;
    expect(await req.post(), hasStatus(400), reason: "omit 'Basic'");

    // Non-base64 data
    req = client.request("/auth/token")
      ..headers = {"Authorization" : "Basic bad"}
      ..formData = m;
    expect(await req.post(), hasStatus(400), reason: "Non-base64 data");

    // Wrong thing
    req = client.clientAuthenticatedRequest("/auth/token", clientID: "foobar")
      ..formData = m;
    expect(await req.post(), hasStatus(401), reason: "Wrong client id");
  });

  test("POST token body failure cases", () async {
    await createUsers(adapter, 2);

    // Missing grant_type
    var req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    expect(await req.post(), hasStatus(400));

    // Invalid grant_type
    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "foobar", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    expect(await req.post(), hasStatus(400));

    // Omit username
    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "password" : "foobaraxegrind21%"};
    expect(await req.post(), hasStatus(400));

    // Invalid user
    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "username" : "bob+24@stablekernel.com", "password" : "foobaraxegrind21%"};
    expect(await req.post(), hasStatus(400));

    // Omit password
    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "username" : "bob+0@stablekernel.com"};
    expect(await req.post(), hasStatus(400));

    // Wrong password
    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "fobar%"};
    expect(await req.post(), hasStatus(401));
  });

  test("Refresh token responds with token on correct input", () async {
    await createUsers(adapter, 1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};

    var req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = m;
    var json = JSON.decode((await req.post()).body);
    m = {"grant_type" : "refresh", "refresh_token" : json["refresh_token"]};

    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = m;
    expect(await req.post(), hasResponse(200, [], matchesJSON({
      "access_token" : hasLength(greaterThan(0)),
      "refresh_token" : hasLength(greaterThan(0)),
      "expires_in" : greaterThan(3500),
      "token_type" : "bearer"
    })));
  });
}

