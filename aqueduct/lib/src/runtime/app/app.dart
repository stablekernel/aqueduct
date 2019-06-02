import 'dart:async';

import 'package:aqueduct/src/application/application.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/application/isolate_supervisor.dart';
import 'package:aqueduct/src/application/options.dart';
import 'package:aqueduct/src/auth/auth.dart';
import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/http/resource_controller.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:logging/logging.dart';

abstract class ChannelRuntime {
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(
      ApplicationChannel channel);

  Type get channelType;

  ApplicationChannel instantiateChannel();

  Future runGlobalInitialization(ApplicationOptions config);

  Future<ApplicationIsolateSupervisor> spawn(
      Application application,
      ApplicationOptions config,
      int identifier,
      Logger logger,
      Duration startupTimeout,
      {bool logToConsole = false});
}

abstract class ControllerRuntime {
  bool get isMutable;

  ResourceControllerRuntime get resourceController;
}

abstract class SerializableRuntime {
  APISchemaObject documentSchema(APIDocumentContext context);
}

abstract class ResourceControllerRuntime {
  List<ResourceControllerOperationRuntime> get operations;

  void bindProperties(ResourceController rc, Request request, List<String> errorsIn);

  ResourceControllerOperationRuntime getOperationRuntime(String method, List<String> pathVariables);

  void documentComponents(ResourceController rc, APIDocumentContext context);

  List<APIParameter> documentOperationParameters(
      ResourceController rc, APIDocumentContext context, Operation operation);

  APIRequestBody documentOperationRequestBody(
      ResourceController rc, APIDocumentContext context, Operation operation);

  Map<String, APIOperation> documentOperations(ResourceController rc,
      APIDocumentContext context, String route, APIPath path);
}

abstract class ResourceControllerOperationRuntime {
  List<AuthScope> scopes;
  List<String> pathVariables;
  String method;

  bool isSuitableForRequest(String requestMethod, List<String> requestPathVariables);
  Future<Response> invoke(ResourceController rc, Request request, List<String> errorsIn);
}