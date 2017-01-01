import 'dart:async';

import 'base.dart';

class CLIAuth extends CLICommand {
  CLIAuth() {
//    options
//      ..addCommand("add-client",)
  }

  Future<int> handle() async {
    return 0;
  }

  Future cleanup() async {

  }

  String get name {
    return "auth";
  }

  String get description {
    return "A tool for adding OAuth 2.0 clients to a database using the managed_auth package.";
  }

}
