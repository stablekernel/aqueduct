part of wildfire;

class RegisterController extends ModelController<User> {
  @httpPost createUser() async {
    if (query.values.username == null || query.values.password == null) {
      return new Response.badRequest(body: {"error": "Username and password required."});
    }

    var salt = AuthenticationServer.generateRandomSalt();
    var hashedPassword = AuthenticationServer.generatePasswordHash(query.values.password, salt);
    query.values.hashedPassword = hashedPassword;
    query.values.salt = salt;

    var u = await query.insert();

    var credentials = AuthorizationBasicParser.parse(request.innerRequest.headers.value(HttpHeaders.AUTHORIZATION));
    var token = await request.permission.grantingServer
        .authenticate(u.username, query.values.password, request.permission.clientID, credentials.password);

    return AuthController.tokenResponse(token);
  }
}
