import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:async';

void main() {
  test("Success case", () {
    var yamlString =
        "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  user: bob\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.user, "bob");
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Missing required top-level explicit", () {
    try {
      var yamlString =
          "name: foobar\n"
          "database:\n"
          "  user: bob\n"
          "  password: fred\n"
          "  name: dbname\n"
          "  port: 5000";

      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "port is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });

  test("Missing required top-level implicit", () {
    try {
      var yamlString =
          "port: 80\n"
          "name: foobar\n";
      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "database is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });

  test("Optional can be missing", () {
    var yamlString =
        "port: 80\n"
        "database:\n"
        "  user: bob\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, isNull);
    expect(t.database.user, "bob");
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested optional can be missing", () {
    var yamlString =
        "port: 80\n"
        "name: foobar\n"
        "database:\n"
        "  password: fred\n"
        "  name: dbname\n"
        "  port: 5000";

    var t = new TopLevelConfiguration(yamlString);
    expect(t.port, 80);
    expect(t.name, "foobar");
    expect(t.database.user, isNull);
    expect(t.database.password, "fred");
    expect(t.database.name, "dbname");
    expect(t.database.port, 5000);
  });

  test("Nested required cannot be missing", () {
    try {
      var yamlString =
          "port: 80\n"
          "name: foobar\n"
          "database:\n"
          "  password: fred\n"
          "  port: 5000";

      var _ = new TopLevelConfiguration(yamlString);
    } on ConfigurationException catch (e) {
      expect(e.message, "name is required but was not found in configuration.");
    } catch (e) {
      expect(true, false, reason: "Should not reach here");
    }
  });
}

class TopLevelConfiguration extends ConfigurationItem {
  TopLevelConfiguration(String contents) {
    loadConfigurationFromString(contents);
  }

  @requiredConfiguration
  int port;

  @optionalConfiguration
  String name;

  DatabaseInfo database;
}

class DatabaseInfo extends ConfigurationItem {
  @optionalConfiguration
  String user;
  @optionalConfiguration
  String password;
  String name;
  int port;
}