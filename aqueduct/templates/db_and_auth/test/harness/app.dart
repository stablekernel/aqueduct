import 'package:wildfire/model/user.dart';
import 'package:wildfire/wildfire.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

export 'package:wildfire/wildfire.dart';
export 'package:aqueduct_test/aqueduct_test.dart';
export 'package:test/test.dart';
export 'package:aqueduct/aqueduct.dart';

/// A testing harness for wildfire.
///
/// A harness for testing an aqueduct application. Example test file:
///
///         void main() {
///           Harness harness = new Harness();
///           setUpAll(() async {
///             await harness.setUp();
///           });
///
///           tearDownAll(() async {
///             await harness.tearDown();
///           });
///
///           test("Make request", () async {
///             final req = harness.defaultClient.request("/path");
///             expectResponse(await req.get(), 200);
///           });
///         }
///
class Harness extends TestHarness<WildfireChannel> with TestHarnessManagedAuthMixin<WildfireChannel>, TestHarnessORMMixin {
  @override
  ManagedContext get context => channel.context;

  @override
  AuthServer get authServer => channel.authServer;

  Agent publicAgent;

  @override
  Future beforeStart() async {
    // add initialization code that will run prior to the test application starting
  }

  @override
  Future afterStart() async {
    // add initialization code that will run once the test application has started
    await resetData();
  }

  @override
  Future seed() async {
    await addClients();
  }

  // Add your OAuth2 client identifiers in this method.
  // If you resetData, invoke this method in its restore.
  Future addClients() async {
    publicAgent = await addClient("com.aqueduct.public");
  }

  Future<Agent> registerUser(User user, {Agent withClient}) async {
    withClient ??= publicAgent;

    final req = withClient.request("/register")
      ..body = {"username": user.username, "password": user.password};
    await req.post();

    return loginUser(withClient, user.username, user.password);
  }
}