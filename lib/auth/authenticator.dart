part of monadart;

class Authenticator extends RequestHandler {
  static const String StrategyResourceOwner = "StrategyResourceOwner";
  static const String StrategyClient = "StrategyClient";
  static const String StrategyOptionalResourceOwner = "StrategyOptionalResourceOwner";

  static const String PermissionKey = "PermissionKey";
  AuthenticationServer server;
  List<String> strategies;

  Authenticator(this.server, this.strategies);

  @override
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    var errorResponse = null;
    for (var strategy in strategies) {
      if (strategy == Authenticator.StrategyResourceOwner) {
        var result = processResourceOwnerRequest(req);
        if (result is ResourceRequest) {
          return result;
        }

        errorResponse = result;
      } else if (strategy == Authenticator.StrategyClient) {
        var result = processClientRequest(req);
        if (result is ResourceRequest) {
          return result;
        }

        errorResponse = result;
      } else if (strategy == Authenticator.StrategyOptionalResourceOwner) {
        var result = processOptionalResourceOwner(req);
        if (result is ResourceRequest) {
          return result;
        }
        errorResponse = result;
      }
    }

    if (errorResponse == null) {
      errorResponse = new Response.serverError();
    }

    return errorResponse;
  }

  Future<RequestHandlerResult> processResourceOwnerRequest(ResourceRequest req) async {
    var parser = new AuthorizationBearerParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    if(parser.errorResponse != null) {
      return parser.errorResponse;
    }

    var permission = await server.verify(parser.bearerToken);
    req.context[PermissionKey] = permission;
    return req;
  }

  Future<RequestHandlerResult> processClientRequest(ResourceRequest req) async {
    var parser = new AuthorizationBasicParser(req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first);
    if (parser.errorResponse != null) {
      return parser.errorResponse;
    }

    var client = await server.clientForID(parser.username);
    if (client == null) {
      return new Response.unauthorized();
    }

    if (client.hashedSecret != AuthenticationServer.generatePasswordHash(parser.password, client.salt)) {
      return new Response.unauthorized();
    }

    var perm = new Permission(client.id, null, server);
    req.context[PermissionKey] = perm;

    return req;
  }

  Future<RequestHandlerResult> processOptionalResourceOwner(ResourceRequest req) async {
    var authHeader = req.innerRequest.headers[HttpHeaders.AUTHORIZATION]?.first;
    if (authHeader == null) {
      return req;
    }

    return processResourceOwnerRequest(req);
  }
}
