import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import '../helpers.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  ManagedContext context = null;
  AuthDelegate delegate;
  AuthServer authServer;
  HttpServer server;
  String accessToken;
  String expiredErrorToken;

  setUp(() async {
    context = await contextWithModels([TestUser, Token, AuthCode]);
    delegate = new AuthDelegate(context);
    authServer = new AuthServer<TestUser, Token, AuthCode>(delegate);
    var _ = (await createUsers(1)).first;

    accessToken = (await authServer.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro")).accessToken;
    expiredErrorToken = (await authServer.authenticate("bob+0@stablekernel.com", "foobaraxegrind21%", "com.stablekernel.app1", "kilimanjaro", expirationInSeconds: 0)).accessToken;
  });

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;

    await server?.close();
  });

  group("Bearer Token", () {
    test("No bearer token returns 401", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed authorization bearer header returns 400", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Notbearer"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error" : "invalid_authorization_header"});
    });

    test("Malformed, but has credential identifier, authorization bearer header returns 400", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Bearer "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error" : "invalid_authorization_header"});
    });

    test("Invalid bearer token returns 401", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Bearer 1234567890asdfghjkl"});
      expect(res.statusCode, 401);
    });

    test("Expired bearer token returns 401", () async {
      var authorizer = new Authorizer.bearer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Bearer $expiredErrorToken"});
      expect(res.statusCode, 401);
    });

    test("Valid bearer token returns authorization object", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Bearer $accessToken"});
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {"clientID" : "com.stablekernel.app1", "resourceOwnerIdentifier" : 1});
    });
  });

  group("Basic Credentials", () {
    test("No basic auth header returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000");
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Malformed basic authorization header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Notright"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error" : "invalid_authorization_header"});
    });

    test("Basic authorization, but empty, header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Basic "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error" : "invalid_authorization_header"});
    });

    test("Basic authorization, but bad data after Basic identifier, header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Basic asasd"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error" : "invalid_authorization_header"});
    });

    test("Invalid client id returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Basic ${new Base64Encoder().convert("abcd:kilimanjaro".codeUnits)}"});
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Invalid client secret returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Basic ${new Base64Encoder().convert("com.stablekernel.app1:foobar".codeUnits)}"});
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Valid client ID returns 200 with authorization", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {HttpHeaders.AUTHORIZATION : "Basic ${new Base64Encoder().convert("com.stablekernel.app1:kilimanjaro".codeUnits)}"});
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {"clientID" : "com.stablekernel.app1", "resourceOwnerIdentifier" : null});
    });
  });

  group("Scoping", () {
    test("nyi", () async {
      fail("NYI");
    });
  });

}

Future<HttpServer> enableAuthorizer(Authorizer authorizer) async {
  var router = new Router();
  router.route("/").pipe(authorizer).listen(respond);
  router.finalize();

  var server = await HttpServer.bind(InternetAddress.ANY_IP_V4, 8000);
  server.map((httpReq) => new Request(httpReq)).listen(router.receive);

  return server;
}


Future<RequestControllerEvent> respond(Request req) async {
  return new Response.ok({
    "clientID": req.authorization.clientID,
    "resourceOwnerIdentifier": req.authorization.resourceOwnerIdentifier
  });
}