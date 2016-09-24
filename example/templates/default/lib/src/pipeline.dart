part of wildfire;

class WildfireConfiguration extends ConfigurationItem {
  WildfireConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
  int port;
}

class WildfirePipeline extends ApplicationPipeline {
  static const String ConfigurationKey = "ConfigurationKey";
  static const String LoggingTargetKey = "LoggingTargetKey";

  WildfirePipeline(Map<String, dynamic> opts) : super(opts) {
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
        .thenDeliver(authenticationServer.newAuthenticator(strategy: AuthenticationStrategy.Client))
        .thenGenerate(() => new AuthController(authenticationServer));

    router
        .route("/auth/code")
        .thenDeliver(authenticationServer.newAuthenticator(strategy: AuthenticationStrategy.Client))
        .thenGenerate(() => new AuthCodeController(authenticationServer));

    router
        .route("/identity")
        .thenDeliver(authenticationServer.newAuthenticator())
        .thenGenerate(() => new IdentityController());

    router
        .route("/register")
        .thenDeliver(authenticationServer.newAuthenticator(strategy: AuthenticationStrategy.Client))
        .thenGenerate(() => new RegisterController());

    router
        .route("/users/[:id]")
        .thenDeliver(authenticationServer.newAuthenticator())
        .thenGenerate(() => new UserController());
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
    Iterable<ClassMirror> allClasses = libMirror.declarations.values
        .where((decl) => decl is ClassMirror);

    return allClasses
        .where((m) => m.isSubclassOf(modelMirror))
        .map((m) => m.reflectedType)
        .toList();
  }
}
