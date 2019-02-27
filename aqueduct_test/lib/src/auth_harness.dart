import 'dart:async';
import 'dart:convert';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

/// Use methods from this class to test applications that use [AuthServer] for authentication & authorization.
///
/// This class is mixed in to your [TestHarness] subclass to provide test
/// utilities for applications that use OAuth2.
///
/// Methods from this class add client identifiers and authenticate users for
/// the purpose of executing authenticated requests in your tests.
///
/// You must override [authServer] to return your application's [AuthServer] service,
/// and [application] to return your harness' application.
///
/// This mixin is typically used with [TestHarnessORMMixin] and `package:aqueduct/managed_auth`.
/// Invoke [addClient] in [TestHarnessORMMixin.seed] to add OAuth2 clients that will survive
/// [TestHarnessORMMixin.resetData].
///
///         class Harness extends TestHarness<MyChannel>
///           with TestHarnessManagedAuthMixin<MyChannel>, TestHarnessORMMixin {
///             Agent publicAgent;
///
///             @override
///             AuthServer get authServer => channel.authServer;
///
///             @override
///             Application<T> get application => channel.application;
///
///             Future seed() async {
///               // Create a new OAuth2 client that users can authenticate with
///               publicAgent = await addClient("com.public.client");
///             }
///         }
abstract class TestHarnessAuthMixin<T extends ApplicationChannel>
    implements TestHarness<T> {
  /// Must override to return [authServer] of application under test.
  ///
  /// An [ApplicationChannel] should expose its [AuthServer] service as a property.
  /// Return that [AuthServer] from this method, e.g.,
  ///
  ///             AuthServer get authServer => channel.authServer;
  AuthServer get authServer;

  /// Creates a new OAuth2 client identifier and returns an [Agent] that makes requests on behalf of that client.
  ///
  /// A new [AuthClient] is added to the [authServer]'s database. Returns an [Agent] that will
  /// execute requests with a basic authorization header that contains [id] and [secret].
  ///
  /// If [secret] is null, [redirectUri] is ignored (public clients cannot have a redirect URI).
  ///
  /// NOTE: This method adds rows to a database table managed by your test application and [TestHarnessORMMixin.resetData]
  /// will delete those rows. To ensure clients exist for all tests, add clients in [TestHarnessORMMixin.seed].
  Future<Agent> addClient(String id,
      {String secret, String redirectUri, List<String> allowedScope}) async {
    final client = AuthClient.public(id,
        allowedScopes: allowedScope?.map((s) => AuthScope(s))?.toList());

    if (secret != null) {
      client
        ..salt = AuthUtility.generateRandomSalt()
        ..hashedSecret = AuthUtility.generatePasswordHash(secret, client.salt)
        ..redirectURI = redirectUri;
    }

    await authServer.addClient(client);

    final authorizationHeader =
        "Basic ${base64.encode("$id:${secret ?? ""}".codeUnits)}";
    return Agent.from(agent)..headers["authorization"] = authorizationHeader;
  }

  /// Authenticates a user for [username] and [password].
  ///
  /// This method attempts to authenticates [username] for [password], and issues an access token if successful.
  /// The returned [Agent] provides that access token in the authorization header of its requests.
  ///
  /// [fromAgent] must be a client authenticated agent, typically created by [addClient]. If [scopes] is non-null,
  /// the access token will have the included scope if valid.
  Future<Agent> loginUser(Agent fromAgent, String username, String password,
      {List<String> scopes}) async {
    final authorizationHeader = fromAgent.headers["authorization"];
    if (authorizationHeader is! String) {
      throw ArgumentError("expected header 'Authorization' to have String type");
    }
    const parser = AuthorizationBasicParser();
    final credentials = parser.parse(authorizationHeader as String);

    try {
      final token = await authServer.authenticate(
          username, password, credentials.username, credentials.password,
          requestedScopes: scopes?.map((s) => AuthScope(s))?.toList());
      return Agent.from(fromAgent)
        ..headers["authorization"] = "Bearer ${token.accessToken}";
    } on AuthServerException catch (e) {
      if (e.reason == AuthRequestError.invalidGrant) {
        throw ArgumentError("Invalid username/password.");
      } else if (e.reason == AuthRequestError.invalidScope) {
        throw ArgumentError(
            "Scope not permitted for client identifier and/or user.");
      }

      rethrow;
    }
  }
}
