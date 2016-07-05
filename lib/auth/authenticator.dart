part of aqueduct;

/// The type of authentication strategy to use for an [Authenticator].
enum AuthenticationStrategy {
  /// The resource owner strategy requires that a [Request] have a Bearer token.
  ResourceOwner,

  /// The client strategy requires that the [Request] have a Basic Authorization Client ID and Client secret.
  Client
}

/// A [RequestHandler] that will authorize further passage in a [RequestHandler] chain via an [AuthenticationStrategy].
///
/// An instance of [Authenticator] will validate a [Request] given a [strategy] with its [server].
/// If the [Request] is unauthorized, it will respond with the appropriate status code and prevent
/// further request processing. If the [Request] is valid, it will attach a [Permission]
/// to the [Request] and deliver it to the next [RequestHandler].
class Authenticator extends RequestHandler {
  /// Creates an instance of [Authenticator] with a reference back to its [server] and a [strategy].
  Authenticator(this.server, this.strategy) {
    policy = null;
  }

  /// A reference to the [AuthenticationServer] for which this [Authenticator] belongs to.
  AuthenticationServer server;

  /// The [AuthenticationStrategy] for authenticating a request.
  AuthenticationStrategy strategy;

  @override
  Future<RequestHandlerResult> processRequest(Request req) async {
    var errorResponse = null;
    if (strategy == AuthenticationStrategy.ResourceOwner) {
      var result = _processResourceOwnerRequest(req);
      if (result is Request) {
        return result;
      }

      errorResponse = result;
    } else if (strategy == AuthenticationStrategy.Client) {
      var result = _processClientRequest(req);
      if (result is Request) {
        return result;
      }

      errorResponse = result;
    }

    if (errorResponse == null) {
      errorResponse = new Response.serverError();
    }
    
    return errorResponse;
  }

  Future<RequestHandlerResult> _processResourceOwnerRequest(Request req) async {
    var bearerToken = AuthorizationBearerParser.parse(req.innerRequest.headers.value(HttpHeaders.AUTHORIZATION));
    var permission = await server.verify(bearerToken);

    req.permission = permission;

    return req;
  }

  Future<RequestHandlerResult> _processClientRequest(Request req) async {
    var parser = AuthorizationBasicParser.parse(req.innerRequest.headers.value(HttpHeaders.AUTHORIZATION));
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


  @override
  List<APIOperation> document(PackagePathResolver resolver) {
    List<APIOperation> items = nextHandler.document(resolver);

//    items.forEach((i) {
//      if (strategy == AuthenticationStrategy.Client) {
//        i.securityItemName = "client_auth";
//      } else if (strategy == AuthenticationStrategy.ResourceOwner) {
//        i.securityItemName = "token";
//      }
//    });

    return items;
  }
}
