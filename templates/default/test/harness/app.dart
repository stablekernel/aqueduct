import 'package:wildfire/wildfire.dart';
import 'package:aqueduct/test.dart';

export 'package:wildfire/wildfire.dart';
export 'package:aqueduct/test.dart';
export 'package:test/test.dart';
export 'package:aqueduct/aqueduct.dart';

/// A testing harness for wildfire.
///
/// Use instances of this class to start/stop the test wildfire server. Use [client] to execute
/// requests against the test server.  This instance will use configuration values
/// from config.src.yaml.
class TestApplication {
  TestClient client;
  Application<WildfireChannel> application;

  WildfireChannel get channel => application.channel;

  String get configurationFilePath => "config.src.yaml";

  /// Starts running this test harness.
  ///
  /// This method will start an [Application] with [WildfireChannel]. Invoke this method
  /// in setUpAll (or setUp, depending on your need).
  ///
  /// You must call [stop] on this instance when tearing down your tests.
  Future start() async {
    Controller.letUncaughtExceptionsEscape = true;
    application = new Application<WildfireChannel>()
      ..options.port = 0
      ..options.configurationFilePath = configurationFilePath;

    await application.test();

    client = new TestClient(application);
  }

  /// Stops running this application harness.
  ///
  /// This method must be invoked in tearDownAll or tearDown to free up operating system
  /// resources.
  Future stop() async {
    await application?.stop();
  }
}
