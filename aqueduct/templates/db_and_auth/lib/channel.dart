import 'wildfire.dart';

import 'controller/identity_controller.dart';
import 'controller/register_controller.dart';
import 'controller/user_controller.dart';
import 'model/user.dart';
import 'utility/html_template.dart';

/// This type initializes an application.
///
/// Override methods in this class to set up routes and initialize services like
/// database connections. See http://aqueduct.io/docs/http/channel/.
class WildfireChannel extends ApplicationChannel implements AuthCodeControllerDelegate {
  HTMLRenderer htmlRenderer = new HTMLRenderer();
  AuthServer authServer;
  ManagedContext context;

  /// Initialize services in this method.
  ///
  /// Implement this method to initialize services, read values from [options]
  /// and any other initialization required before constructing [entryPoint].
  ///
  /// This method is invoked prior to [entryPoint] being accessed.
  @override
  Future prepare() async {
    logger.onRecord.listen((rec) => print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

    var config = new WildfireConfiguration(options.configurationFilePath);

    context = contextWithConnectionInfo(config.database);

    var authStorage = new ManagedAuthDelegate<User>(context);
    authServer = new AuthServer(authStorage);
  }

  /// Construct the request channel.
  ///
  /// Return an instance of some [Controller] that will be the initial receiver
  /// of all [Request]s.
  ///
  /// This method is invoked after [prepare].
  @override
  Controller get entryPoint {
    final router = new Router();

    /* OAuth 2.0 Endpoints */
    router.route("/auth/token").link(() => new AuthController(authServer));

    router.route("/auth/code").link(() => new AuthCodeController(authServer, delegate: this));

    /* Create an account */
    router
        .route("/register")
        .link(() => new Authorizer.basic(authServer))
        .link(() => new RegisterController(context, authServer));

    /* Gets profile for user with bearer token */
    router.route("/me").link(() => new Authorizer.bearer(authServer)).link(() => new IdentityController(context));

    /* Gets all users or one specific user by id */
    router
        .route("/users/[:id]")
        .link(() => new Authorizer.bearer(authServer))
        .link(() => new UserController(context, authServer));

    return router;
  }

  /*
   * Helper methods
   */

  ManagedContext contextWithConnectionInfo(DatabaseConfiguration connectionInfo) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore(connectionInfo.username, connectionInfo.password, connectionInfo.host,
        connectionInfo.port, connectionInfo.databaseName);

    return new ManagedContext(dataModel, psc);
  }

  @override
  Future<String> render(AuthCodeController forController, Uri requestUri, String responseType, String clientID,
      String state, String scope) async {
    var map = {"response_type": responseType, "client_id": clientID, "state": state};

    map["path"] = requestUri.path;
    if (scope != null) {
      map["scope"] = scope;
    }

    return htmlRenderer.renderHTML("web/login.html", map);
  }
}

/// An instance of this class represents values from a configuration
/// file specific to this application.
///
/// Configuration files must have key-value for the properties in this class.
/// For more documentation on configuration files, see
/// https://pub.dartlang.org/packages/safe_config.
class WildfireConfiguration extends Configuration {
  WildfireConfiguration(String fileName) : super.fromFile(new File(fileName));

  DatabaseConfiguration database;
}
