import 'package:aqueduct/src/runtime/resource_controller_impl.dart';
import 'package:runtime/runtime.dart';

String getResourceControllerImplSource(ResourceControllerRuntimeImpl runtime, BuildContext context) {
  return """
class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {  
  List<ResourceControllerOperationRuntime> get operations {
    return [];
  }
  
  void bindProperties(ResourceController rc, Request request, List<String> errorsIn) {
  
  }
  
  ResourceControllerOperationRuntime getOperationRuntime(String method, List<String> pathVariables) {
    return null;
  }
  
  void documentComponents(ResourceController rc, APIDocumentContext context) => throw StateError('not valid in compiled app');
  
  List<APIParameter> documentOperationParameters(
    ResourceController rc, APIDocumentContext context, Operation operation) => throw StateError('not valid in compiled app');
  
  APIRequestBody documentOperationRequestBody(
    ResourceController rc, APIDocumentContext context, Operation operation) => throw StateError('not valid in compiled app');
  
  Map<String, APIOperation> documentOperations(ResourceController rc,
    APIDocumentContext context, String route, APIPath path) => throw StateError('not valid in compiled app');
}      
  """;
}

