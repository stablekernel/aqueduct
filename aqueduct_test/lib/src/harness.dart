import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

/// Manages application lifecycle for the purpose of testing the application.
///
/// You install a test harness at the beginning of a test's `main` function. Before test cases are run,
/// the harness starts an instance of your application on the same isolate as the tests. After your tests complete,
/// the harness stops the application from running.
///
/// You typically create a subclass of [TestHarness] that is used for all tests in an application. The subclass
/// overrides callbacks [beforeStart] and [afterStart] to configure the application. This configuration might be
/// adding an application's database schema to a test database, or to create OAuth2 client identifiers
/// for use during test. See also [TestHarnessORMMixin] and [TestHarnessAuthMixin] for adding common behaviors
/// like these to your harness.
///
/// Usage:
///
///         class Harness extends ApplicationHarness<MyChannel> {
///           @override
///           Future afterStart() async {
///             channel.service.uri = Uri.parse("http://localhost:4040");
///           }
///         }
///
///         void main() {
///           final harness = new Harness()..install();
///
///           test("GET /example returns 200", () async {
///             final response = await harness.agent.get("/example");
///             expectResponse(response, 200);
///           });
///         }
class TestHarness<T extends ApplicationChannel> {
  /// The application being tested.
  ///
  /// In [beforeStart], this value is the application that will be started. In [afterStart],
  /// this value is the application that is currently running.
  ///
  /// After [tearDown], this value becomes null.
  Application<T> get application => _application;

  /// The channel of the running application.
  ///
  /// Use this property to access the channel and its properties during startup or tests.
  T get channel => application.channel;

  /// The default [Agent] that makes requests to the application being tested.
  Agent agent;

  /// Application options for the application being tested.
  ///
  /// Values must be set in [beforeStart] for changes to have an effect on running application.
  ///
  /// Default values: [ApplicationOptions.port] is `0`, and [ApplicationOptions.configurationFilePath] is `config.src.yaml`.
  ApplicationOptions options = new ApplicationOptions()
    ..port = 0
    ..configurationFilePath = "config.src.yaml";

  Application<T> _application;

  /// Installs this handler to automatically start before tests begin running,
  ///
  /// This method invokes [setUpAll] to start the teswt application, and [tearDownAll] to stop it.
  /// You should invoke this method at the top of your `main` function in a test file.
  ///
  /// To start and stop the application manually, see [setUp] and [tearDown].
  void install() {
    setUpAll(() async {
      await setUp();
    });

    tearDownAll(() async {
      await tearDown();
    });
  }

  /// Initializes a test application and starts it.
  ///
  /// Runs all before initializers, starts the application under test, and then runs all after initializers.
  ///
  /// Prefer to use [install] instead of calling this method manually.
  Future setUp() async {
    Controller.letUncaughtExceptionsEscape = true;

    _application = new Application<T>()..options = options;

    await beforeStart();
    await application.test();
    agent = new Agent(application);
    await afterStart();
  }

  /// Stops the test application from running.
  ///
  /// Stops application from listening to requests and calls its tear down behavior. [application]
  /// is set to null.
  ///
  /// Prefer to use [install] instead of calling this method manually.
  Future tearDown() async {
    await application?.stop();
    _application = null;
  }

  /// Override this method to provide configuration for the application under test.
  ///
  /// This method is invoked after [application] is created, but before it is started.
  /// All configuration information to be performed prior to creating [ApplicationChannel]s
  /// and listening for requests must be provided by this method.
  ///
  /// By default, does nothing.
  Future beforeStart() async {}


  /// Override this method to provide post-startup behavior for the application under test.
  ///
  /// This method is invoked after the application has started. Use this method to add
  /// database schemas to the test database, add test data, etc.
  ///
  /// By default, does nothing.
  Future afterStart() async {}
}