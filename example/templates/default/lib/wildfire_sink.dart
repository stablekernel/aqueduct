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

    authenticationServer = new AuthServer<User, Token, AuthCode>(
        new WildfireAuthenticationDelegate());
  }

  ManagedContext context;
  AuthServer<User, Token, AuthCode> authenticationServer;

  /// All routes must be configured in this method.
  @override
  void setupRouter(Router router) {
    router
        .route("/auth/token")
        .pipe(
            new Authorizer(authenticationServer, strategy: AuthStrategy.client))
        .generate(() => new AuthController(authenticationServer));

    router
        .route("/auth/code")
        .pipe(
            new Authorizer(authenticationServer, strategy: AuthStrategy.client))
        .generate(() => new AuthCodeController(authenticationServer));

    router
        .route("/identity")
        .pipe(new Authorizer(authenticationServer))
        .generate(() => new IdentityController());

    router
        .route("/register")
        .pipe(
            new Authorizer(authenticationServer, strategy: AuthStrategy.client))
        .generate(() => new RegisterController());

    router
        .route("/users/[:id]")
        .pipe(new Authorizer(authenticationServer))
        .generate(() => new UserController());
  }

  ManagedContext contextWithConnectionInfo(
      DatabaseConnectionConfiguration connectionInfo) {
    var dataModel =
        new ManagedDataModel.fromPackageContainingType(this.runtimeType);
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        connectionInfo.username,
        connectionInfo.password,
        connectionInfo.host,
        connectionInfo.port,
        connectionInfo.databaseName);

    var ctx = new ManagedContext(dataModel, psc);
    ManagedContext.defaultContext = ctx;

    return ctx;
  }

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
      PackagePathResolver resolver) {
    return authenticationServer.documentSecuritySchemes(resolver);
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