import '../wildfire.dart';

class RegisterController extends QueryController<User> {
  @httpPost
  createUser() async {
    if (query.values.email == null || query.values.password == null) {
      return new Response.badRequest(
          body: {"error": "email and password required."});
    }
    var credentials = AuthorizationBasicParser
        .parse(request.innerRequest.headers.value(HttpHeaders.AUTHORIZATION));

    var salt = AuthServer.generateRandomSalt();
    var hashedPassword =
        AuthServer.generatePasswordHash(query.values.password, salt);
    query.values.hashedPassword = hashedPassword;
    query.values.salt = salt;

    var u = await query.insert();
    var token = await request.authorization.grantingServer.authenticate(
        u.username,
        query.values.password,
        request.authorization.clientID,
        credentials.password);

    return AuthController.tokenResponse(token);
  }
}
