import 'package:aqueduct/src/http/resource_controller.dart';
import 'package:aqueduct/src/runtime/resource_controller_impl.dart';
import 'package:runtime/runtime.dart';

String getInvokerSource(ResourceControllerOperationRuntimeImpl op, ResourceControllerRuntimeImpl controller, BuildContext context) {
  final buf = StringBuffer();

  buf.writeln("(rc, request, errorsIn) async {");

  op.positionalParameters.forEach((parameter) {

  });

  buf.writeln("}");

  return buf.toString();
}

String getResourceControllerImplSource(
    ResourceControllerRuntimeImpl runtime, BuildContext context) {
  final runtimes = runtime.operations.map((op) {
    return "ResourceControllerOperationRuntimeImpl('${op.method}', "
      "[${op.pathVariables.map((p) => "'$p'").join(",")}],"
      "[${op.scopes?.map((s) => "'$s'")?.join(",") ?? ""}],"
      "${getInvokerSource(op, runtime, context)})";
  }).join(",\n");


  return """
class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {  
  @override
  List<ResourceControllerOperationRuntimeImpl> operations = [
    $runtimes
  ];

  void bindProperties(ResourceController rc, Request request, List<String> errorsIn) {
  
  }
  
  void documentComponents(ResourceController rc, APIDocumentContext context) => throw StateError('not valid in compiled app');
  
  List<APIParameter> documentOperationParameters(
    ResourceController rc, APIDocumentContext context, Operation operation) => throw StateError('not valid in compiled app');
  
  APIRequestBody documentOperationRequestBody(
    ResourceController rc, APIDocumentContext context, Operation operation) => throw StateError('not valid in compiled app');
  
  Map<String, APIOperation> documentOperations(ResourceController rc,
    APIDocumentContext context, String route, APIPath path) => throw StateError('not valid in compiled app');
}

class ResourceControllerOperationRuntimeImpl extends ResourceControllerOperationRuntime {
  ResourceControllerOperationRuntimeImpl(String method, List<String> pathVariables, List<AuthScope> scopes, this.invoker) {
    this.scopes = scopes;
    this.pathVariables = pathVariables;
    this.method = method;
  }
  
  final Future<Response> Function(
      ResourceController rc, Request request, List<String> errorsIn) invoker;
      
  @override
  Future<Response> invoke(
      ResourceController rc, Request request, List<String> errorsIn) => invoker(rc, request, errorsIn);
}
  """;
}
