import 'dart:io';

import 'response.dart';
import 'controller.dart';
import 'request.dart';


//class HTTPResponseException implements Exception {
//  /// Creates an instance of a [HTTPResponseException].
//  HTTPResponseException(this.statusCode, this.message, {this.isControlFlowException: true});
//
//  /// The message to return to the client.
//  ///
//  /// This message will be JSON encoded in a Map for the key 'error'.
//  final String message;
//
//  /// Whether or not this is a control flow exception.
//  ///
//  /// A control flow exception is considered normal behavior by an application.
//  /// When [Controller.letUncaughtExceptionsEscape] is true, a control flow exception
//  /// will not escape and will instead be caught silently.
//  ///
//  /// By default, this value is true.
//  bool isControlFlowException = true;
//
//  /// The status code of the [Response].
//  final int statusCode;
//
//  /// A [Response] object derived from this exception.
//  Response get response {
//    return new Response(statusCode, null, {"error": message})..contentType = ContentType.JSON;
//  }
//}
//
