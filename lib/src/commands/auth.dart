import 'dart:async';
import 'package:aqueduct/managed_auth.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';

import 'base.dart';

class CLIAuth extends CLICommand {
  CLIAuth() {
    registerCommand(new CLIAuthAddClient());
//    options
//      ..addCommand("add-client",)
  }

  Future<int> handle() async {
    printHelp(parentCommandName: "aqueduct");
    return 0;
  }

  Future cleanup() async {}

  String get name {
    return "auth";
  }

  String get description {
    return "A tool for adding OAuth 2.0 clients to a database using the managed_auth package.";
  }

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

class CLIAuthAddClient extends CLIDatabaseConnectingCommand {
  CLIAuthAddClient() {
    options
      ..addOption("id", abbr: "i", help: "The client ID to insert.")
      ..addOption("secret",
          abbr: "s",
          help:
              "The client secret. This secret will be hashed on insertion, so you *must* store it somewhere. For public clients, this option may be omitted.")
      ..addOption("redirect-uri",
          abbr: "r",
          help:
              "The redirect URI of the client if it supports the authorization code flow. May be omitted.");
  }

  String get clientID => values["id"];
  String get secret => values["secret"];
  String get redirectUri => values["redirect-uri"];

  Future<int> handle() async {
    if (clientID == null) {
      displayError("Option --id required.");
      return 1;
    }

    if (secret == null && redirectUri != null) {
      displayError(
          "A client that supports the authorization code flow must be a confidential client");
      displayProgress(
          "Using option --redirect-uri creates a client that supports the authorization code flow. Either provide --secret or remove --redirect-uri.");
      return 1;
    }

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var context = new ManagedContext(dataModel, persistentStore);

    var credentials = AuthUtility.generateAPICredentialPair(clientID, secret,
        redirectURI: redirectUri);
    var managedCredentials = new ManagedClient()
      ..id = credentials.id
      ..hashedSecret = credentials.hashedSecret
      ..salt = credentials.salt
      ..redirectURI = credentials.redirectURI;

    var query = new Query<ManagedClient>(context)..values = managedCredentials;

    try {
      await query.insert();

      displayInfo("Success", color: CLIColor.green);
      displayProgress("Client with ID '$clientID' has been added.");
      displayProgress(
          "The client secret has been hashed. You must store it elsewhere, as it cannot be retrieved.");
      return 0;
    } on QueryException catch (e) {
      displayError("Adding Client Failed");
      if (e.event == QueryExceptionEvent.conflict) {
        PostgreSQLException underlying = e.underlyingException;
        if (underlying.constraintName == "_authclient_redirecturi_key") {
          displayProgress(
              "Redirect URI '${redirectUri}' already exists for another client.");
        } else {
          displayProgress("Client ID '${clientID}' already exists.");
        }

        return 1;
      }

      var underlying = e.underlyingException;
      if (underlying is PostgreSQLException) {
        if (underlying.code == PostgreSQLErrorCode.undefinedTable) {
          displayProgress(
              "No table to store OAuth 2.0 client exists. Have you run 'aqueduct db upgrade'?");
        }
      }
    }

    return 1;
  }

  String get name {
    return "add-client";
  }

  String get description {
    return "Adds an OAuth 2.0 client to a database when the database has been provisioned with the aqueduct/managed_auth package.";
  }
}

class FauxAuthenticatable extends ManagedObject<_FauxAuthenticatable> {}

class _FauxAuthenticatable extends ManagedAuthenticatable {}
