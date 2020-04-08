import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:test/test.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  group("Operations and security schemes", () {
    APIDocument doc;

    setUpAll(() async {
      doc = await Application.document(TestChannel, ApplicationOptions(),
          {"name": "Test", "version": "1.0"});
    });

    test("AuthServer documents components", () {
      final schemes = doc.components.securitySchemes;

      expect(schemes.length, 2);
      expect(schemes["oauth2"].type, APISecuritySchemeType.oauth2);
      expect(schemes["oauth2-client-authentication"].type,
          APISecuritySchemeType.http);
      expect(schemes["oauth2-client-authentication"].scheme, "basic");
    });

    test(
        "Basic Authorizer adds oauth2 client authentication to operations for all paths",
        () {
      final noVarPath = doc.paths["/basic"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements,
          {"oauth2-client-authentication": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements,
          {"oauth2-client-authentication": []});

      final varPath = doc.paths["/basic/{id}"];
      expect(varPath.operations.length, 1);
      expect(varPath.operations["get"].security.length, 1);
      expect(varPath.operations["get"].security.first.requirements,
          {"oauth2-client-authentication": []});
    });

    test("No scope bearer authorizer adds oauth2 authentication to operations",
        () {
      final noVarPath = doc.paths["/bearer-no-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements,
          {"oauth2": []});
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements,
          {"oauth2": []});
    });

    test(
        "Scoped bearer authorizer adds oauth2 authentication to operations w/ scope",
        () {
      final noVarPath = doc.paths["/bearer-scope"];
      expect(noVarPath.operations.length, 2);
      expect(noVarPath.operations["get"].security.length, 1);
      expect(noVarPath.operations["get"].security.first.requirements, {
        "oauth2": ["scope"]
      });
      expect(noVarPath.operations["post"].security.length, 1);
      expect(noVarPath.operations["post"].security.first.requirements, {
        "oauth2": ["scope"]
      });
    });

    test(
        "Authorizer does not prevent linked controllers from registering components",
        () {
      expect(doc.components.schemas["verifyComponents"].type, APIType.string);
    });

    test("Authorizer adds Forbidden and Unauthorized to response components",
        () {
      expect(
          doc.components.responses["InsufficientScope"].description, isNotNull);
      expect(
          doc.components.responses["InsufficientScope"]
              .content["application/json"].schema.type,
          APIType.object);
      expect(
          doc.components.responses["InsufficientScope"]
              .content["application/json"].schema.properties["error"].type,
          APIType.string);
      expect(
          doc.components.responses["InsufficientScope"]
              .content["application/json"].schema.properties["scope"].type,
          APIType.string);

      expect(doc.components.responses["InsufficientAccess"].description,
          isNotNull);

      expect(
          doc.components.responses["MalformedAuthorizationHeader"].description,
          isNotNull);
    });

    test("Bearer Authorizer adds 401 and 403 response to operations", () {
      final noVarPath = doc.paths["/bearer-no-scope"];
      expect(noVarPath.operations["get"].responses["403"].referenceURI.path,
          "/components/responses/InsufficientScope");
      expect(noVarPath.operations["get"].responses["401"].referenceURI.path,
          "/components/responses/InsufficientAccess");
      expect(noVarPath.operations["get"].responses["400"].referenceURI.path,
          "/components/responses/MalformedAuthorizationHeader");
    });

    test("Basic Authorizer adds 401 and 403 response to operations", () {
      final noVarPath = doc.paths["/basic"];
      expect(noVarPath.operations["get"].responses["403"].referenceURI.path,
          "/components/responses/InsufficientScope");
      expect(noVarPath.operations["get"].responses["401"].referenceURI.path,
          "/components/responses/InsufficientAccess");

      final varPath = doc.paths["/basic/{id}"];
      expect(varPath.operations["get"].responses["403"].referenceURI.path,
          "/components/responses/InsufficientScope");
      expect(varPath.operations["get"].responses["401"].referenceURI.path,
          "/components/responses/InsufficientAccess");
    });
  });

  group("Controller Registration and Scopes", () {
    test(
        "If no controllers added to channel, do not support have flows for oauth2 security type",
        () async {
      final doc = await Application.document(TestChannel, ApplicationOptions(),
          {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows, {});
    });

    test(
        "If only AuthController added to channel, do not support auth code flow",
        () async {
      final doc = await Application.document(AuthControllerOnlyChannel,
          ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"].refreshURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"].tokenURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"]
              .authorizationURL,
          isNull);
      expect(doc.components.securitySchemes["oauth2"].flows["password"].scopes,
          {});
    });

    test(
        "If both AuthController and AuthRedirectController added to channel, support both flows and have appropriate urls",
        () async {
      final doc = await Application.document(ScopedControllerChannel,
          ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"].refreshURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"].tokenURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["password"]
              .authorizationURL,
          isNull);

      expect(
          doc.components.securitySchemes["oauth2"].flows["authorizationCode"]
              .refreshURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["authorizationCode"]
              .tokenURL,
          Uri(path: "auth/token"));
      expect(
          doc.components.securitySchemes["oauth2"].flows["authorizationCode"]
              .authorizationURL,
          Uri(path: "auth/code"));
    });

    test(
        "Referenced scopes for supported flows are available in oauth2 flow map",
        () async {
      final doc = await Application.document(ScopedControllerChannel,
          ApplicationOptions(), {"name": "Test", "version": "1.0"});
      expect(doc.components.securitySchemes["oauth2"].flows["password"].scopes,
          {"scope1": "", "scope2": ""});
      expect(
          doc.components.securitySchemes["oauth2"].flows["authorizationCode"]
              .scopes,
          {"scope1": "", "scope2": ""});
    });
  });
}

class TestChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = AuthServer(InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    // Note that AuthRedirectController/AuthController are not added to channel.
    // This supports a test in 'Controller Registration and Scopes'.

    final router = Router();

    router
        .route("/basic/[:id]")
        .link(() => Authorizer.basic(authServer))
        .link(() => DocumentedController());
    router
        .route("/bearer-no-scope")
        .link(() => Authorizer.bearer(authServer))
        .link(() => DocumentedController());
    router
        .route("/bearer-scope")
        .link(() => Authorizer.bearer(authServer, scopes: ["scope"]))
        .link(() => DocumentedController(tag: "verifyComponents"));
    return router;
  }
}

class DocumentedController extends Controller {
  DocumentedController({this.tag});

  final String tag;

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext components, String route, APIPath path) {
    if (path.containsPathParameters([])) {
      return {
        "get": APIOperation("get/0", {
          "200": APIResponse("get/0-200", content: {
            "application/json": APIMediaType(schema: APISchemaObject.string())
          })
        }),
        "post": APIOperation("post/0", {
          "200": APIResponse("post/0-200", content: {
            "application/json": APIMediaType(schema: APISchemaObject.string())
          })
        })
      };
    }

    return {
      "get": APIOperation("get/1", {
        "200": APIResponse("get/1-200", content: {
          "application/json": APIMediaType(schema: APISchemaObject.string())
        })
      })
    };
  }

  @override
  void documentComponents(APIDocumentContext context) {
    super.documentComponents(context);
    if (tag != null) {
      context.schema.register(tag, APISchemaObject.string());
    }
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return Response.ok("foo");
  }
}

class AuthControllerOnlyChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = AuthServer(InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/auth/token").link(() => AuthController(authServer));
    return router;
  }
}

class ScopedControllerChannel extends ApplicationChannel {
  AuthServer authServer;

  @override
  Future prepare() async {
    authServer = AuthServer(InMemoryAuthStorage());
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router.route("/auth/token").link(() => AuthController(authServer));
    router.route("/auth/code").link(() => AuthRedirectController(authServer));
    router
        .route("/r1")
        .link(() => Authorizer.bearer(authServer, scopes: ["scope1"]))
        .link(() => DocumentedController());
    router
        .route("/r2")
        .link(() => Authorizer.bearer(authServer, scopes: ["scope1", "scope2"]))
        .link(() => DocumentedController());

    router
        .route("/r3")
        .link(() => Authorizer.bearer(authServer))
        .link(() => DocumentedController());
    return router;
  }
}
