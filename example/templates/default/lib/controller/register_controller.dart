import '../wildfire.dart';

class RegisterController extends QueryController<User> {
  RegisterController(this.authServer);

  AuthServer authServer;

  @httpPost
  createUser() async {
    if (query.values.username == null || query.values.password == null) {
      return new Response.badRequest(
          body: {"error": "username and password required."});
    }
    var credentials = AuthorizationBasicParser
        .parse(request.innerRequest.headers.value(HttpHeaders.AUTHORIZATION));

    var salt = AuthUtility.generateRandomSalt();
    var hashedPassword =
      AuthUtility.generatePasswordHash(query.values.password, salt);
    query.values.hashedPassword = hashedPassword;
    query.values.salt = salt;

    var u = await query.insert();
    var token = await authServer.authenticate(
        u.username,
        query.values.password,
        credentials.username,
        credentials.password);

    return AuthController.tokenResponse(token);
  }
}
