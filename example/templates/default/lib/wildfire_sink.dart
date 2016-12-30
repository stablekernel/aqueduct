import 'wildfire.dart';

/// This class handles setting up this application.
///
/// Override methods from [RequestSink] to set up the resources your
/// application uses and the routes it exposes.
///
/// See the documentation in this file for [initializeApplication], [WildfireSink], [setupRouter] and [willOpen]
/// for the purpose and order of the initialization methods.
///
/// Instances of this class are the type argument to [Application].
/// See http://stablekernel.github.io/aqueduct/http/request_sink.html
/// for more details.
class WildfireSink extends RequestSink {
  static const String ConfigurationValuesKey = "ConfigurationValuesKey";
  static const String LoggingTargetKey = "LoggingTargetKey";

  HTMLRenderer htmlRenderer = new HTMLRenderer();
  ManagedContext context;
  AuthServer authServer;

  /// Do one-time application setup in this method.
  ///
  /// This method is executed before any instances of this type are created and is the first step in the initialization process.
  ///
  /// Values can be added to [config]'s [ApplicationConfiguration.options] and will be available in each instance of this class
  /// in the constructor. The values added to the configuration's options are often from a configuration file that this method reads.
  static Future initializeApplication(ApplicationConfiguration config) async {
    var configFileValues = new WildfireConfiguration(config.configurationFilePath);
    config.options[ConfigurationValuesKey] = configFileValues;

    var loggingServer = configFileValues.logging.loggingServer;
    config.options[LoggingTargetKey] = loggingServer?.getNewTarget();

    await loggingServer?.start();
  }

  /// Constructor called for each isolate run by an [Application].
  ///
  /// This constructor is called for each isolate an [Application] creates to serve requests - therefore,
  /// any initialization that must occur only once per application startup should happen in [initializeApplication].
  ///
  /// This constructor is invoked after [initializeApplication].
  ///
  /// The [options] are provided by the command line arguments and script that starts the application, and often
  /// contain values that [initializeApplication] adds to it.
  ///
  /// Resources that require asynchronous initialization, such as database connections, should be instantiated in this
  /// method but should be opened in [willOpen].
  WildfireSink(ApplicationConfiguration options) : super(options) {
    WildfireConfiguration configuration = options.options[ConfigurationValuesKey];

    LoggingTarget target = options.options[LoggingTargetKey];
    target?.bind(logger);

    context = contextWithConnectionInfo(configuration.database);
    ManagedContext.defaultContext = context;

    authServer = new AuthServer(new ManagedAuthStorage<User>(context));
  }

  /// All routes must be configured in this method.
  ///
  /// This method is invoked after the constructor and before [willOpen] Routes must be set up in this method, as
  /// the router gets 'compiled' after this method completes and routes cannot be added later.
  @override
  void setupRouter(Router router) {
    router
        .route("/register")
        .pipe(new Authorizer.basic(authServer))
        .generate(() => new RegisterController(authServer));

    router
        .route("/me")
        .pipe(new Authorizer.bearer(authServer))
        .generate(() => new IdentityController());

    router
        .route("/users/[:id]")
        .pipe(new Authorizer.bearer(authServer))
        .generate(() => new UserController(authServer));

    router.route("/auth/token").generate(() => new AuthController(authServer));

    router.route("/auth/code").generate(() => new AuthCodeController(authServer,
        renderAuthorizationPageHTML: renderLoginPage));
  }

  /// Final initialization method for this instance.
  ///
  /// This method allows any resources that require asynchronous initialization to complete their
  /// initialization process. This method is invoked after [setupRouter] and prior to this
  /// instance receiving any requests.
  Future willOpen() async {

  }

  ManagedContext contextWithConnectionInfo(
      DatabaseConnectionConfiguration connectionInfo) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        connectionInfo.username,
        connectionInfo.password,
        connectionInfo.host,
        connectionInfo.port,
        connectionInfo.databaseName);

    return new ManagedContext(dataModel, psc);
  }

  Future<String> renderLoginPage(AuthCodeController controller, Uri requestURI,
      Map<String, String> queryParameters) async {
    var path = requestURI.path;
    var map = new Map<String, String>.from(queryParameters);
    map["path"] = path;

    return htmlRenderer.renderHTML("web/login.html", map);
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
  LoggingConfiguration logging;
}

class LoggingConfiguration extends ConfigurationItem {
  static const String TypeConsole = "console";
  static const String TypeFile = "file";

  String type;

  @optionalConfiguration
  String filename;

  LoggingServer _loggingServer;
  LoggingServer get loggingServer {
    if (_loggingServer == null) {
      if (type == LoggingConfiguration.TypeConsole) {
        _loggingServer = new LoggingServer([new ConsoleBackend()]);
      } else if (type == LoggingConfiguration.TypeFile) {
        var logPath = filename ?? "api.log";
        _loggingServer = new LoggingServer([new RotatingLoggingBackend(logPath)]);
      }
    }
    return _loggingServer;
  }
}