import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:io';
import '../helpers.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  InMemoryAuthStorage delegate;
  AuthServer authServer;
  HttpServer server;
  String accessToken;
  String expiredErrorToken;

  setUp(() async {
    delegate = new InMemoryAuthStorage();
    delegate.createUsers(1);

    authServer = new AuthServer(delegate);

    accessToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro"))
        .accessToken;
    expiredErrorToken = (await authServer.authenticate(
            delegate.users[1].username,
            InMemoryAuthStorage.DefaultPassword,
            "com.stablekernel.app1",
            "kilimanjaro",
            expiration: new Duration(seconds: 0)))
        .accessToken;
  });

  tearDown(() async {
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

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Notbearer"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Malformed, but has credential identifier, authorization bearer header returns 400",
        () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid bearer token returns 401", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer 1234567890asdfghjkl"});
      expect(res.statusCode, 401);
    });

    test("Expired bearer token returns 401", () async {
      var authorizer = new Authorizer.bearer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer $expiredErrorToken"});
      expect(res.statusCode, 401);
    });

    test("Valid bearer token returns authorization object", () async {
      var authorizer = new Authorizer(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Bearer $accessToken"});
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body),
          {"clientID": "com.stablekernel.app1", "resourceOwnerIdentifier": 1});
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

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Notright"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Basic authorization, but empty, header returns 400", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Basic "});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test(
        "Basic authorization, but bad data after Basic identifier, header returns 400",
        () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000",
          headers: {HttpHeaders.AUTHORIZATION: "Basic asasd"});
      expect(res.statusCode, 400);
      expect(JSON.decode(res.body), {"error": "invalid_authorization_header"});
    });

    test("Invalid client id returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("abcd:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Invalid client secret returns 401", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:foobar".codeUnits)}"
      });
      expect(res.statusCode, 401);
      expect(res.body, "");
    });

    test("Valid client ID returns 200 with authorization", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:kilimanjaro".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {
        "clientID": "com.stablekernel.app1",
        "resourceOwnerIdentifier": null
      });
    });

    test("Public client can only be authorized with no password", () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.public:".codeUnits)}"
      });
      expect(res.statusCode, 200);
      expect(JSON.decode(res.body), {
        "clientID": "com.stablekernel.public",
        "resourceOwnerIdentifier": null
      });

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.public:password".codeUnits)}"
      });
      expect(res.statusCode, 401);
    });

    test("Confidential client can never be authorized with no password",
        () async {
      var authorizer = new Authorizer.basic(authServer);
      server = await enableAuthorizer(authorizer);

      var res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1:".codeUnits)}"
      });
      expect(res.statusCode, 401);

      res = await http.get("http://localhost:8000", headers: {
        HttpHeaders.AUTHORIZATION:
            "Basic ${new Base64Encoder().convert("com.stablekernel.app1".codeUnits)}"
      });
      expect(res.statusCode, 400);
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
