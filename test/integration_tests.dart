import 'package:inquirer_pgsql/inquirer_pgsql.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'package:monadart/monadart.dart';
import 'package:http/http.dart' as http;
import 'helpers.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'dart:convert';
main() async {
  var app = new Application<TPipeline, ResourceRequest>();
  app.configuration.port = 8080;
  await app.start();

  var tc = new TestClient()
    ..host = "http://localhost:8080"
    ..defaultClientID = "com.stablekernel.app1"
    ..defaultClientSecret = "kilimanjaro";

  test("Can create user", () async {
    var response = await (tc.clientAuthenticatedJSONRequest("/users")..json = {
      "username" : "bob@stablekernel.com",
      "password" : "axespin16&"
    }).post();
    expect(response.statusCode, 200);
    expect(response.hasOnlyKeys(["access_token", "refresh_token", "token_type", "expires_in"]), true);

    tc.token = response.json;

    response = await (tc.authenticatedJSONRequest("/identity")).get();
    expect(response.statusCode, 200);
    expect(response.json["username"], "bob@stablekernel.com");
  });
}

class TPipeline extends ApplicationPipeline {
  Router router = new Router();

  PostgresModelAdapter adapter = new PostgresModelAdapter(null, () async {
    var uri = 'postgres://dart:dart@localhost:5432/dart_test';
    return await connect(uri);
  });

  AuthenticationServer<TestUser, Token> authenticationServer;

  @override
  RequestHandler initialHandler() {
    return router;
  }

  @override
  Future willReceiveRequest(ResourceRequest req) async {
    req.context["adapter"] = adapter;
  }

  @override
  Future willOpen() async {
    await generateTemporarySchemaFromModels(adapter, [TestUser, Token]);

    adapter.loggingEnabled = true;

    authenticationServer = new AuthenticationServer<TestUser, Token>(
        new AuthDelegate<TestUser, Token>(adapter));

    router.route(AuthController.RoutePattern).then(new RequestHandlerGenerator<AuthController<TestUser, Token>>());
    router.route("/users")
        .then(authenticationServer.authenticator(strategies: [Authenticator.StrategyResourceOwner, Authenticator.StrategyClient]))
        .then(new RequestHandlerGenerator<UsersController>());
    router.route("/identity")
        .then(authenticationServer.authenticator())
        .then(new RequestHandlerGenerator<IdentityController>());
  }
}

class IdentityController extends HttpController {
  PostgresModelAdapter get adapter => request.context["adapter"];
  Permission get permission => request.context[Authenticator.PermissionKey];

  @httpGet
  Future<Response> getIdentity() async {
    var q = new Query<TestUser>()
        ..resultKeys = ["username", "id"]
        ..predicateObject = (new TestUser()..id = permission.resourceOwnerIdentifier);

    var user = await q.fetchOne(adapter);
    if (user == null) {
      return new Response.notFound();
    }

    return new Response.ok(user.asMap());
  }
}

class UsersController extends HttpController {
  PostgresModelAdapter get adapter => request.context["adapter"];
  Permission get permission => request.context[Authenticator.PermissionKey];

  @httpPost
  Future<Response> createUser() async {
    if (permission.resourceOwnerIdentifier != null) {
      return new Response.badRequest();
    }

    var password = requestBody["password"];
    var salt = AuthenticationServer.generateRandomSalt();
    var hashedPassword = AuthenticationServer.generatePasswordHash(password, salt);
    var u = new TestUser()
      ..username = requestBody["username"]
      ..hashedPassword = hashedPassword
      ..salt = salt;

    var q = new Query<TestUser>()
      ..resultKeys = ["username", "id"]
      ..valueObject = u;
    u = await q.insert(adapter);

    var token = await permission.grantingServer.authenticate(u.username,
        password,
        permission.clientID, "kilimanjaro");

    return AuthController.tokenResponse(token);
  }
}
