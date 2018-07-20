import '../model/user.dart';
import '../wildfire.dart';

class RegisterController extends QueryController<User> {
  RegisterController(ManagedContext context, this.authServer) : super(context);

  AuthServer authServer;

  @Operation.post()
  Future<Response> createUser() async {
    if (query.values.username == null || query.values.password == null) {
      return Response.badRequest(
          body: {"error": "username and password required."});
    }

    final salt = AuthUtility.generateRandomSalt();
    final hashedPassword = authServer.hashPassword(query.values.password, salt);

    query.values.hashedPassword = hashedPassword;
    query.values.salt = salt;
    query.values.email = query.values.username;

    final u = await query.insert();
    final token = await authServer.authenticate(
        u.username,
        query.values.password,
        request.authorization.credentials.username,
        request.authorization.credentials.password);

    return AuthController.tokenResponse(token);
  }
}
