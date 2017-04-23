/// Testing utilities for Aqueduct applications
///
/// This library should be imported in test scripts. It should not be imported in application code.
///
/// Example:
///
/// import 'package:test/test.dart';
/// import 'package:aqueduct/aqueduct.dart';
/// import 'package:aqueduct/test.dart';
///
/// void main() {
///   test("...", () async => ...);
/// }
library aqueduct.test;

export 'src/utilities/mock_server.dart';
export 'src/utilities/test_client.dart';
export 'src/utilities/test_matchers.dart';
