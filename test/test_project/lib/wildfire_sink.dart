import 'wildfire.dart';

/// This class handles setting up this application.
///
/// Override methods from [RequestSink] to set up the resources your
/// application uses and the routes it exposes.
///
/// Instances of this class are the type argument to [Application].
/// See http://stablekernel.github.io/aqueduct/http/request_sink.html
/// for more details.
///
/// See bin/start.dart for usage.
class WildfireSink extends RequestSink {
  static const String ConfigurationKey = "ConfigurationKey";
  static const String LoggingTargetKey = "LoggingTargetKey";

  /// [Application] creates instances of this type with this constructor.
  ///
  /// The options will be the values set in the spawning [Application]'s
  /// [Application.configuration] [ApplicationConfiguration.configurationOptions].
  /// See bin/start.dart.
  WildfireSink(Map<String, dynamic> opts) : super(opts) {
    WildfireConfiguration configuration = opts[ConfigurationKey];

    LoggingTarget target = opts[LoggingTargetKey];
    target?.bind(logger);

    context = contextWithConnectionInfo(configuration.database);
    ManagedContext.defaultContext = context;

    authServer = new AuthServer(new ManagedAuthStorage<User>(context));
  }

  ManagedContext context;
  AuthServer authServer;

  /// All routes must be configured in this method.
  @override
  void setupRouter(Router router) {
    router
        .route("/auth/token")
        .generate(() => new AuthController(authServer));

    router
        .route("/auth/code")
        .generate(() => new AuthCodeController(authServer));

    router
        .route("/register")
        .generate(() => new RegisterController(authServer));

    router
        .route("/me")
        .pipe(new Authorizer.bearer(authServer))
        .generate(() => new IdentityController());

    router
        .route("/users/[:id]")
        .pipe(new Authorizer.bearer(authServer))
        .generate(() => new UserController(authServer));
  }

  ManagedContext contextWithConnectionInfo(
      DatabaseConnectionConfiguration connectionInfo) {
    var dataModel =
        new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        connectionInfo.username,
        connectionInfo.password,
        connectionInfo.host,
        connectionInfo.port,
        connectionInfo.databaseName);

    return new ManagedContext(dataModel, psc);
  }

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
      PackagePathResolver resolver) {
    return authServer.documentSecuritySchemes(resolver);
  }
}

/// An instance of this class represents values from a configuration
/// file specific to this application.
///
/// Configuration files must have key-value for the properties in this class.
/// For more documentation on configuration files, see
/// https://pub.dartlang.org/packages/safe_config.
class WildfireConfiguration extends ConfigurationItem {
  WildfireConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
  int port;
}