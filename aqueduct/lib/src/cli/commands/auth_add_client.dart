import 'dart:async';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/database_connecting.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:crypto/crypto.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:aqueduct/aqueduct.dart';

class CLIAuthAddClient extends CLICommand
    with CLIDatabaseConnectingCommand, CLIDatabaseManagingCommand, CLIProject {
  @Option("id", abbr: "i", help: "The client ID to insert.")
  String get clientID => decode("id");

  @Option("secret",
      abbr: "s",
      help:
          "The client secret. This secret will be hashed on insertion, so you *must* store it somewhere. For public clients, this option may be omitted.")
  String get secret => decode("secret");

  @Option("redirect-uri",
      abbr: "r",
      help:
          "The redirect URI of the client if it supports the authorization code or implicit flow. May be omitted.")
  String get redirectUri => decode("redirect-uri");

  @Option("hash-function",
      help:
          "Hash function to apply when hashing secret. Must match AuthServer.hashFunction.",
      defaultsTo: "sha256",
      allowed: ["sha256", "sha1", "md5"])
  Hash get hashFunction {
    switch (decode<String>("hash-function")) {
      case "sha256":
        return sha256;
      case "sha1":
        return sha1;
      case "md5":
        return md5;
      default:
        throw CLIException(
            "Value '${decode("hash-function")}' is not valid for option hash-function.");
    }
  }

  @Option("hash-rounds",
      help:
          "Number of hash rounds to apply to secret. Must match AuthServer.hashRounds.",
      defaultsTo: "1000")
  int get hashRounds => decode("hash-rounds");

  @Option("hash-length",
      help:
          "Length in bytes of secret key after hashing. Must match AuthServer.hashLength.",
      defaultsTo: "32")
  int get hashLength => decode("hash-length");

  @Option("allowed-scopes",
      help:
          "A space-delimited list of allowed scopes. Omit if application does not support scopes.",
      defaultsTo: "")
  List<String> get allowedScopes {
    String v = decode("allowed-scopes") as String;
    if (v.isEmpty) {
      return null;
    }
    return v?.split(" ")?.toList();
  }

  ManagedContext context;

  @override
  Future<int> handle() async {
    if (clientID == null) {
      displayError("Option --id required.");
      return 1;
    }

    var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    context = ManagedContext(dataModel, persistentStore);

    var credentials = AuthUtility.generateAPICredentialPair(clientID, secret,
        redirectURI: redirectUri,
        hashLength: hashLength,
        hashRounds: hashRounds,
        hashFunction: hashFunction)
      ..allowedScopes = allowedScopes?.map((s) => AuthScope(s))?.toList();

    var managedCredentials = ManagedAuthClient.fromClient(credentials);

    final query = Query<ManagedAuthClient>(context)
      ..values = managedCredentials;

    try {
      await query.insert();

      displayInfo("Success", color: CLIColor.green);
      displayProgress("Client with ID '$clientID' has been added.");
      if (secret != null) {
        displayProgress(
            "The client secret has been hashed. You must store it elsewhere, as it cannot be retrieved.");
      }
      if (managedCredentials.allowedScope != null) {
        displayProgress("Allowed scope: ${managedCredentials.allowedScope}");
      }
      return 0;
    } on QueryException catch (e) {
      if (e.event == QueryExceptionEvent.conflict) {
        if (e.offendingItems.contains("id")) {
          displayError("Client ID '$clientID' already exists.");
        } else if (e.offendingItems.contains("redirectURI")) {
          displayError("Redirect URI '$redirectUri' already exists.");
        }

        return 1;
      }

      rethrow;
    }
  }

  @override
  Future cleanup() async {
    await context?.close();
  }

  @override
  String get name {
    return "add-client";
  }

  @override
  String get description {
    return "Adds an OAuth 2.0 client to a database when the database has been provisioned with the aqueduct/managed_auth package.";
  }
}

// This is required to build the data model that contains ManagedAuthClient.
// Some table definition must implement ManagedAuthenticatable to fulfill
// this data model's requirements.
class FauxAuthenticatable extends ManagedObject<_FauxAuthenticatable> {}

class _FauxAuthenticatable extends ResourceOwnerTableDefinition {}
