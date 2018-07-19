import '../model/user.dart';
import '../wildfire.dart';

class UserController extends QueryController<User> {
  UserController(ManagedContext context, this.authServer) : super(context);

  AuthServer authServer;

  @Operation.get("id")
  Future<Response> getUser(@Bind.path("id") int id) async {
    final u = await query.fetchOne();
    if (u == null) {
      return Response.notFound();
    }

    if (request.authorization.ownerID != id) {
      // Filter out stuff for non-owner of user
    }

    return Response.ok(u);
  }

  @Operation.put("id")
  Future<Response> updateUser(@Bind.path("id") int id) async {
    if (request.authorization.ownerID != id) {
      return Response.unauthorized();
    }

    final u = await query.updateOne();
    if (u == null) {
      return Response.notFound();
    }

    return Response.ok(u);
  }

  @Operation.delete("id")
  Future<Response> deleteUser(@Bind.path("id") int id) async {
    if (request.authorization.ownerID != id) {
      return Response.unauthorized();
    }

    await authServer.revokeAllGrantsForResourceOwner(id);
    await query.delete();

    return Response.ok(null);
  }
}
