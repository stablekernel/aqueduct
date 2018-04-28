import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:aqueduct/managed_auth.dart';
import 'package:aqueduct/aqueduct.dart';

import 'base.dart';

class CLIAuth extends CLICommand {
  CLIAuth() {
    registerCommand(new CLIAuthAddClient());
    registerCommand(new CLIAuthScopeClient());
  }

  @override
  Future<int> handle() async {
    printHelp(parentCommandName: "aqueduct");
    return 0;
  }

  @override
  Future cleanup() async {}

  @override
  String get name {
    return "auth";
  }

  @override
  String get description {
    return "A tool for adding OAuth 2.0 clients to a database using the managed_auth package.";
  }

  @override
  String get detailedDescription {
    return "Some commands require connecting to a database to perform their action. These commands will "
        "have options for --connect and --database-config in their usage instructions."
        "You may either use a connection string (--connect) or a database configuration (--database-config) to provide "
        "connection details. The format of a connection string is: \n\n"
        "\tpostgres://username:password@host:port/databaseName\n\n"
        "A database configuration file is a YAML file with the following format:\n\n"
        "\tusername: \"user\"\n"
        "\tpassword: \"password\"\n"
        "\thost: \"host\"\n"
        "\tport: port\n"
        "\tdatabaseName: \"database\"";
  }
}

class CLIAuthScopeClient extends CLIDatabaseConnectingCommand {
  CLIAuthScopeClient() {
    options
      ..addOption("scopes",
          help: "A space-delimited list of allowed scopes. Omit if application does not support scopes.",
          defaultsTo: "")
      ..addOption("id", abbr: "i", help: "The client ID to insert.");
  }

  ManagedContext context;

  String get clientID => values["id"];

  List<String> get scopes {
    var v = values["scopes"] as String;
    if (v.isEmpty) {
      return null;
    }
    return v?.split(" ")?.toList();
  }

  @override
  Future<int> handle() async {
    if (clientID == null) {
      displayError("Option --id required.");
      return 1;
    }
    if ((scopes?.isEmpty ?? true)) {
      displayError("Option --scopes required.");
      return 1;
    }

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    context = new ManagedContext(dataModel, persistentStore);

    var scopingClient = new AuthClient.public(clientID, allowedScopes: scopes?.map((s) => new AuthScope(s))?.toList());

    var query = new Query<ManagedAuthClient>(context)
      ..where((o) => o.id).equalTo(clientID)
      ..values.allowedScope = scopingClient.allowedScopes?.map((s) => s.toString())?.join(" ");

    var result = await query.updateOne();
    if (result == null) {
      displayError("Client ID '$clientID' does not exist.");
      return 1;
    }

    displayInfo("Success", color: CLIColor.green);
    displayProgress("Client with ID '$clientID' has been updated.");
    displayProgress("Updated scope: ${result.allowedScope}");
    return 0;
  }

  @override
  Future cleanup() async {
    await context?.close();
  }

  @override
  String get name {
    return "set-scope";
  }

  @override
  String get description {
    return "Sets the scope of an existing OAuth 2.0 client in a database that has been provisioned with the aqueduct/managed_auth package.";
  }
}

class CLIAuthAddClient extends CLIDatabaseConnectingCommand {
  CLIAuthAddClient() {
    options
      ..addOption("allowed-scopes",
          help: "A space-delimited list of allowed scopes. Omit if application does not support scopes.",
          defaultsTo: "")
      ..addOption("id", abbr: "i", help: "The client ID to insert.")
      ..addOption("hash-rounds",
          help: "Number of hash rounds to apply to secret. Must match AuthServer.hashRounds.", defaultsTo: "1000")
      ..addOption("hash-length",
          help: "Length in bytes of secret key after hashing. Must match AuthServer.hashLength.", defaultsTo: "32")
      ..addOption("hash-function",
          help: "Hash function to apply when hashing secret. Must match AuthServer.hashFunction.",
          defaultsTo: "sha256",
          allowed: ["sha256", "sha1", "md5"])
      ..addOption("secret",
          abbr: "s",
          help:
              "The client secret. This secret will be hashed on insertion, so you *must* store it somewhere. For public clients, this option may be omitted.")
      ..addOption("redirect-uri",
          abbr: "r",
          help: "The redirect URI of the client if it supports the authorization code flow. May be omitted.");
  }

  ManagedContext context;

  String get clientID => values["id"];

  String get secret => values["secret"];

  String get redirectUri => values["redirect-uri"];

  Hash get hashFunction {
    switch (values["hash-function"]) {
      case "sha256":
        return sha256;
      case "sha1":
        return sha1;
      case "md5":
        return md5;
      default:
        throw new CLIException("Value '${values["hash-function"]}' is not valid for option hash-function.");
    }
  }

  int get hashRounds => int.parse(values["hash-rounds"]);

  int get hashLength => int.parse(values["hash-length"]);

  List<String> get allowedScopes {
    var v = values["allowed-scopes"] as String;
    if (v.isEmpty) {
      return null;
    }
    return v?.split(" ")?.toList();
  }

  @override
  Future<int> handle() async {
    if (clientID == null) {
      displayError("Option --id required.");
      return 1;
    }

    if (secret == null && redirectUri != null) {
      displayError("A client that supports the authorization code flow must be a confidential client");
      displayProgress(
          "Using option --redirect-uri creates a client that supports the authorization code flow. Either provide --secret or remove --redirect-uri.");
      return 1;
    }

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    context = new ManagedContext(dataModel, persistentStore);

    var credentials = AuthUtility.generateAPICredentialPair(clientID, secret,
        redirectURI: redirectUri, hashLength: hashLength, hashRounds: hashRounds, hashFunction: hashFunction)
      ..allowedScopes = allowedScopes?.map((s) => new AuthScope(s))?.toList();

    var managedCredentials = new ManagedAuthClient()
      ..id = credentials.id
      ..hashedSecret = credentials.hashedSecret
      ..salt = credentials.salt
      ..redirectURI = credentials.redirectURI
      ..allowedScope = credentials.allowedScopes?.map((s) => s.toString())?.join(" ");

    var query = new Query<ManagedAuthClient>(context)..values = managedCredentials;

    try {
      await query.insert();

      displayInfo("Success", color: CLIColor.green);
      displayProgress("Client with ID '$clientID' has been added.");
      if (secret != null) {
        displayProgress("The client secret has been hashed. You must store it elsewhere, as it cannot be retrieved.");
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

class FauxAuthenticatable extends ManagedObject<_FauxAuthenticatable> {}

class _FauxAuthenticatable extends ManagedAuthenticatable {}
