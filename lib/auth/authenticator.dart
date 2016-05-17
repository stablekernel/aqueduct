part of aqueduct;

enum AuthenticationStrategy { ResourceOwner, Client }

class Authenticator extends RequestHandler {
  AuthenticationServer server;
  AuthenticationStrategy strategy;

  Authenticator(this.server, this.strategy);

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    if (req.innerRequest.method == "OPTIONS") {
      return req;
    }

    var errorResponse = null;
    if (strategy == AuthenticationStrategy.ResourceOwner) {
      var result = processResourceOwnerRequest(req);
      if (result is ResourceRequest) {
        return result;
      }

      errorResponse = result;
    } else if (strategy == AuthenticationStrategy.Client) {
      var result = processClientRequest(req);
      if (result is ResourceRequest) {
        return result;
      }

      errorResponse = result;
    }

    if (errorResponse == null) {
      errorResponse = new Response.serverError();
    }

    return errorResponse;
  }

  Future<RequestHandlerResult> processResourceOwnerRequest(ResourceRequest req) async {
    var parser = new AuthorizationBearerParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    var permission = await server.verify(parser.bearerToken);

    req.permission = permission;

    return req;
  }

  Future<RequestHandlerResult> processClientRequest(ResourceRequest req) async {
    var parser = new AuthorizationBasicParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    var client = await server.clientForID(parser.username);

    if (client == null) {
      return new Response.unauthorized();
    }

    if (client.hashedSecret != AuthenticationServer.generatePasswordHash(parser.password, client.salt)) {
      return new Response.unauthorized();
    }

    var perm = new Permission(client.id, null, server);
    req.permission = perm;

    return req;
  }


  List<APIDocumentItem> document(PackagePathResolver resolver) {
    List<APIDocumentItem> items = nextHandler.document(resolver);

    items.forEach((i) {
      if (strategy == AuthenticationStrategy.Client) {
        i.securityItemName = "client_auth";
      } else if (strategy == AuthenticationStrategy.ResourceOwner) {
        i.securityItemName = "token";
      }
    });

    return items;
  }
}
