/*
  This example demonstrates an HTTP application that uses the ORM and ORM-backed OAuth2 provider.

  For building and running non-example applications, install 'aqueduct' command-line tool.

      pub global activate aqueduct
      aqueduct create my_app

  More examples available: https://github.com/stablekernel/aqueduct_examples
 */

import 'dart:async';
import 'dart:io';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

Future main() async {
  final app = Application<App>()
    ..options.configurationFilePath = 'config.yaml'
    ..options.port = 8888;

  await app.start(numberOfInstances: 3);
}

class App extends ApplicationChannel {
  ManagedContext context;
  AuthServer authServer;

  @override
  Future prepare() async {
    final config =
        AppConfiguration.fromFile(File(options.configurationFilePath));
    final db = config.database;
    final persistentStore = PostgreSQLPersistentStore.fromConnectionInfo(
        db.username, db.password, db.host, db.port, db.databaseName);
    context = ManagedContext(
        ManagedDataModel.fromCurrentMirrorSystem(), persistentStore);

    authServer = AuthServer(ManagedAuthDelegate(context));
  }

  @override
  Controller get entryPoint {
    return Router()
      ..route('/auth/token').link(() => AuthController(authServer))
      ..route('/users/[:id]')
          .link(() => Authorizer(authServer))
          .link(() => UserController(context, authServer));
  }
}

class UserController extends ResourceController {
  UserController(this.context, this.authServer);

  final ManagedContext context;
  final AuthServer authServer;

  @Operation.get()
  Future<Response> getUsers() async {
    final query = Query<User>(context);
    return Response.ok(await query.fetch());
  }

  @Operation.get('id')
  Future<Response> getUserById(@Bind.path('id') int id) async {
    final q = Query<User>(context)..where((o) => o.id).equalTo(id);
    final user = await q.fetchOne();

    if (user == null) {
      return Response.notFound();
    }

    return Response.ok(user);
  }

  @Operation.post()
  Future<Response> createUser(@Bind.body() User user) async {
    if (user.username == null || user.password == null) {
      return Response.badRequest(
          body: {"error": "username and password required."});
    }

    final salt = AuthUtility.generateRandomSalt();
    final hashedPassword = authServer.hashPassword(user.password, salt);

    final query = Query<User>(context)
      ..values = user
      ..values.hashedPassword = hashedPassword
      ..values.salt = salt
      ..values.email = user.username;

    final u = await query.insert();
    final token = await authServer.authenticate(
        u.username,
        query.values.password,
        request.authorization.credentials.username,
        request.authorization.credentials.password);

    return AuthController.tokenResponse(token);
  }
}

class AppConfiguration extends Configuration {
  AppConfiguration.fromFile(File file) : super.fromFile(file);

  DatabaseConfiguration database;
}

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner<_User> {
  @Serialize(input: true, output: false)
  String password;
}

class _User extends ResourceOwnerTableDefinition {
  @Column(unique: true)
  String email;
}
