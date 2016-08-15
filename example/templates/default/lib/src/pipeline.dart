part of wildfire;

class WildfireConfiguration extends ConfigurationItem {
  WildfireConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
  int port;
}

class WildfirePipeline extends ApplicationPipeline {
  static const String ConfigurationFileKey = "ConfigurationFileKey";
  static const String LoggingTargetKey = "LoggingTargetKey";

  WildfirePipeline(Map<String, dynamic> opts) : super(opts) {
    configuration = new WildfireConfiguration(opts[ConfigurationFileKey]);

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
        .next(authenticationServer.authenticator(strategy: AuthenticationStrategy.Client))
        .next(() => new AuthController(authenticationServer));

    router
        .route("/auth/code")
        .next(authenticationServer.authenticator(strategy: AuthenticationStrategy.Client))
        .next(() => new AuthCodeController(authenticationServer));

    router
        .route("/identity")
        .next(authenticationServer.authenticator())
        .next(() => new IdentityController());

    router
        .route("/register")
        .next(authenticationServer.authenticator(strategy: AuthenticationStrategy.Client))
        .next(() => new RegisterController());

    router
        .route("/users/[:id]")
        .next(authenticationServer.authenticator())
        .next(() => new UserController());
  }

  ModelContext contextWithConnectionInfo(DatabaseConnectionConfiguration database) {
    var connectionInfo = configuration.database;
    var dataModel = new DataModel(modelTypes());
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(connectionInfo.username,
        connectionInfo.password, connectionInfo.host, connectionInfo.port, connectionInfo.databaseName);

    var ctx = new ModelContext(dataModel, psc);
    ModelContext.defaultContext = ctx;

    return ctx;
  }

  static List<Type> modelTypes() {
    var modelMirror = reflectClass(Model);

    LibraryMirror libMirror = reflectType(WildfirePipeline).owner;
    return libMirror.declarations.values
        .where((decl) => decl is ClassMirror)
        .where((ClassMirror m) => m.isSubclassOf(modelMirror))
        .map((ClassMirror m) => m.reflectedType)
        .toList();
  }
}
