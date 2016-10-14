import 'package:test/test.dart';
import 'dart:io';
import 'package:aqueduct/aqueduct.dart';
import 'dart:convert';
import '../helpers.dart';

void main() {
  ModelContext context = null;
  HttpServer server;
  TestClient client = new TestClient(8080)
    ..clientID = "com.stablekernel.app1"
    ..clientSecret = "kilimanjaro";

  var authenticationServer = new AuthenticationServer<TestUser, Token, AuthCode>(new AuthDelegate(context));
  var router = new Router();
  router
      .route("/auth/token")
      .generate(() => new AuthController(authenticationServer));
  router.finalize();

  tearDownAll(() async {
    await server?.close(force: true);
  });

  setUp(() async {
    context = await contextWithModels([TestUser, Token, AuthCode]);

    server = await HttpServer.bind("localhost", 8080, v6Only: false, shared: false);
    server.map((req) => new Request(req)).listen(router.receive);

  });

  tearDown(() async {
    await server?.close(force: true);
    await context?.persistentStore?.close();
    context = null;
    server = null;
  });

  test("POST token responds with token on correct input", () async {
    await createUsers(1);

    var req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    var res = await req.post();

    expect(res, hasResponse(200, {
      "access_token" : hasLength(greaterThan(0)),
      "refresh_token" : hasLength(greaterThan(0)),
      "expires_in" : greaterThan(3500),
      "token_type" : "bearer"
    }));
  });

  test("POST token header failure cases", () async {
    await createUsers(1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};

    var req = client.request("/auth/token")
      ..formData = m;
    expect(await req.post(), hasStatus(400), reason: "omit authorization header");

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
    await createUsers(2);

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
    await createUsers(1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};

    var req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = m;
    var json = JSON.decode((await req.post()).body);
    m = {"grant_type" : "refresh", "refresh_token" : json["refresh_token"]};

    req = client.clientAuthenticatedRequest("/auth/token")
      ..formData = m;
    expect(await req.post(), hasResponse(200, {
      "access_token" : hasLength(greaterThan(0)),
      "refresh_token" : json["refresh_token"],
      "expires_in" : greaterThan(3500),
      "token_type" : "bearer"
    }));
  });

  test("Response documentation", () {
    AuthController ac = new AuthController(new AuthenticationServer(new AuthDelegate(ModelContext.defaultContext)));
    var resolver = new PackagePathResolver(new File(".packages").path);
    var operations = ac.documentOperations(resolver);

    expect(operations.length, 1);

    List<APIResponse> responses = ac.documentResponsesForOperation(operations.first);

    APIResponse okResponse = responses.firstWhere((ar) => ar.key == "${HttpStatus.OK}");
    expect(okResponse.schema.properties["access_token"].type, APISchemaObject.TypeString);
    expect(okResponse.schema.properties["token_type"].type, APISchemaObject.TypeString);
    expect(okResponse.schema.properties["expires_in"].type, APISchemaObject.TypeInteger);
    expect(okResponse.schema.properties["expires_in"].format, APISchemaObject.FormatInt32);
    expect(okResponse.schema.properties["refresh_token"].type, APISchemaObject.TypeString);

    APIResponse badResponse = responses.firstWhere((ar) => ar.key == "${HttpStatus.BAD_REQUEST}");
    expect(badResponse.schema.properties["error"], isNotNull);
  });
}

