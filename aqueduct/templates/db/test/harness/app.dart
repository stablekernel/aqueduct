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
///           Harness harness = new Harness()..install();
///
///           test("GET /path returns 200", () async {
///             final req = harness.defaultClient.request("/path");
///             expectResponse(await req.get(), 200);
///           });
///         }
///
class Harness extends TestHarness<WildfireChannel> with TestHarnessORMMixin {
  @override
  ManagedContext get context => channel.context;

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
    // restore any static data. called afterStart and after resetData
  }
}