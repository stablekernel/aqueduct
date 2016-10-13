part of wildfire;

class WildfireConfiguration extends ConfigurationItem {
  WildfireConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
  int port;
}

class WildfireSink extends RequestSink {
  static const String ConfigurationKey = "ConfigurationKey";
  static const String LoggingTargetKey = "LoggingTargetKey";

  WildfireSink(Map<String, dynamic> opts) : super(opts) {
    configuration = opts[ConfigurationKey];

    LoggingTarget target = opts[LoggingTargetKey];
    target?.bind(logger);

    context = contextWithConnectionInfo(configuration.database);

    authenticationServer = new AuthenticationServer<User, Token, AuthCode>(new WildfireAuthenticationDelegate());
  }

  ModelContext context;
  AuthenticationServer<User, Token, AuthCode> authenticationServer;
  WildfireConfiguration configuration;

  @override
  void addRoutes() {
    router
        .route("/auth/token")
        .pipe(new Authenticator(authenticationServer, strategy: AuthenticationStrategy.client))
        .generate(() => new AuthController(authenticationServer));

    router
        .route("/auth/code")
        .pipe(new Authenticator(authenticationServer, strategy: AuthenticationStrategy.client))
        .generate(() => new AuthCodeController(authenticationServer));

    router
        .route("/identity")
        .pipe(new Authenticator(authenticationServer))
        .generate(() => new IdentityController());

    router
        .route("/register")
        .pipe(new Authenticator(authenticationServer, strategy: AuthenticationStrategy.client))
        .generate(() => new RegisterController());

    router
        .route("/users/[:id]")
        .pipe(new Authenticator(authenticationServer))
        .generate(() => new UserController());
  }

  ModelContext contextWithConnectionInfo(DatabaseConnectionConfiguration database) {
    var connectionInfo = configuration.database;
    var dataModel = new DataModel.fromPackageContainingType(this.runtimeType);
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(connectionInfo.username,
        connectionInfo.password, connectionInfo.host, connectionInfo.port, connectionInfo.databaseName);

    var ctx = new ModelContext(dataModel, psc);
    ModelContext.defaultContext = ctx;

    return ctx;
  }

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) {
    return authenticationServer.documentSecuritySchemes(resolver);
  }

}
