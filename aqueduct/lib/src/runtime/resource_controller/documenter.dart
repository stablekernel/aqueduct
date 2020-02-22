import 'dart:mirrors';

import 'package:aqueduct/src/auth/objects.dart';
import 'package:aqueduct/src/http/resource_controller.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/http/resource_controller_interfaces.dart';
import 'package:aqueduct/src/http/serializable.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/runtime/impl.dart';
import 'package:aqueduct/src/runtime/resource_controller_impl.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

bool isSerializable(Type type) {
  return reflectType(type).isSubtypeOf(reflectType(Serializable));
}

bool isListSerializable(Type type) {
  final boundType = reflectType(type);
  return boundType.isSubtypeOf(reflectType(List)) &&
      boundType.typeArguments.first.isSubtypeOf(reflectType(Serializable));
}

APISchemaObject getSchemaObjectReference(
    APIDocumentContext context, Type type) {
  if (isListSerializable(type)) {
    return APISchemaObject.array(
        ofSchema: context.schema.getObjectWithType(
            reflectType(type).typeArguments.first.reflectedType));
  } else if (isSerializable(type)) {
    return context.schema.getObjectWithType(reflectType(type).reflectedType);
  }

  return null;
}

class ResourceControllerDocumenterImpl extends ResourceControllerDocumenter {
  ResourceControllerDocumenterImpl(this.runtime);

  final ResourceControllerRuntimeImpl runtime;

  @override
  void documentComponents(ResourceController rc, APIDocumentContext context) {
    runtime.operations.forEach((b) {
      [b.positionalParameters, b.namedParameters]
          .expand((b) => b)
          .where((b) => b.location == BindingType.body)
          .forEach((b) {
        final boundType = reflectType(b.type);
        if (isSerializable(b.type)) {
          _registerType(context, boundType);
        } else if (isListSerializable(b.type)) {
          _registerType(context, boundType.typeArguments.first);
        }
      });
    });
  }

  @override
  List<APIParameter> documentOperationParameters(
      ResourceController rc, APIDocumentContext context, Operation operation) {
    bool usesFormEncodedData = operation.method == "POST" &&
        rc.acceptedContentTypes.any((ct) =>
            ct.primaryType == "application" &&
            ct.subType == "x-www-form-urlencoded");

    return parametersForOperation(operation)
        .map((param) {
          if (param.location == BindingType.body) {
            return null;
          }
          if (usesFormEncodedData && param.location == BindingType.query) {
            return null;
          }

          return _documentParameter(context, operation, param);
        })
        .where((p) => p != null)
        .toList();
  }

  @override
  APIRequestBody documentOperationRequestBody(
      ResourceController rc, APIDocumentContext context, Operation operation) {
    final op =
        runtime.getOperationRuntime(operation.method, operation.pathVariables);
    final usesFormEncodedData = operation.method == "POST" &&
        rc.acceptedContentTypes.any((ct) =>
            ct.primaryType == "application" &&
            ct.subType == "x-www-form-urlencoded");
    final boundBody = op.positionalParameters.firstWhere(
            (p) => p.location == BindingType.body,
            orElse: () => null) ??
        op.namedParameters.firstWhere((p) => p.location == BindingType.body,
            orElse: () => null);

    if (boundBody != null) {
      final ref = getSchemaObjectReference(context, boundBody.type);
      if (ref != null) {
        return APIRequestBody.schema(ref,
            contentTypes: rc.acceptedContentTypes
                .map((ct) => "${ct.primaryType}/${ct.subType}"),
            required: boundBody.isRequired);
      }
    } else if (usesFormEncodedData) {
      final Map<String, APISchemaObject> props =
          parametersForOperation(operation)
              .where((p) => p.location == BindingType.query)
              .map((param) => _documentParameter(context, operation, param))
              .fold(<String, APISchemaObject>{}, (prev, elem) {
        prev[elem.name] = elem.schema;
        return prev;
      });

      return APIRequestBody.schema(APISchemaObject.object(props),
          contentTypes: ["application/x-www-form-urlencoded"], required: true);
    }

    return null;
  }

  @override
  Map<String, APIOperation> documentOperations(ResourceController rc,
      APIDocumentContext context, String route, APIPath path) {
    final opsForPath = runtime.operations
        .where((method) => path.containsPathParameters(method.pathVariables));

    return opsForPath.fold(<String, APIOperation>{}, (prev, opObj) {
      final instanceMembers = reflect(rc).type.instanceMembers;
      Operation metadata =
          firstMetadataOfType(instanceMembers[Symbol(opObj.dartMethodName)]);

      final operationDoc = APIOperation(opObj.dartMethodName,
          rc.documentOperationResponses(context, metadata),
          summary: rc.documentOperationSummary(context, metadata),
          description: rc.documentOperationDescription(context, metadata),
          parameters: rc.documentOperationParameters(context, metadata),
          requestBody: rc.documentOperationRequestBody(context, metadata),
          tags: rc.documentOperationTags(context, metadata));

      if (opObj.scopes != null) {
        context.defer(() async {
          operationDoc.security?.forEach((sec) {
            sec.requirements.forEach((name, operationScopes) {
              final secType = context.document.components.securitySchemes[name];
              if (secType?.type == APISecuritySchemeType.oauth2 ||
                  secType?.type == APISecuritySchemeType.openID) {
                _mergeScopes(operationScopes, opObj.scopes);
              }
            });
          });
        });
      }

      prev[opObj.httpMethod.toLowerCase()] = operationDoc;
      return prev;
    });
  }

  List<ResourceControllerParameter> parametersForOperation(Operation op) {
    final operation = runtime.operations.firstWhere(
        (b) => b.isSuitableForRequest(op.method, op.pathVariables),
        orElse: () => null);

    if (operation == null) {
      return [];
    }

    return [
      runtime.ivarParameters,
      operation.positionalParameters,
      operation.namedParameters
    ].expand((i) => i).toList();
  }

  void _mergeScopes(
      List<String> operationScopes, List<AuthScope> methodScopes) {
    final existingScopes = operationScopes.map((s) => AuthScope(s)).toList();

    methodScopes.forEach((methodScope) {
      for (var existingScope in existingScopes) {
        if (existingScope.isSubsetOrEqualTo(methodScope)) {
          operationScopes.remove(existingScope.toString());
        }
      }

      operationScopes.add(methodScope.toString());
    });
  }

  APIParameter _documentParameter(APIDocumentContext context,
      Operation operation, ResourceControllerParameter param) {
    final schema =
        SerializableRuntimeImpl.documentType(context, reflectType(param.type));
    final documentedParameter = APIParameter(param.name, param.apiLocation,
        schema: schema,
        required: param.isRequired,
        allowEmptyValue: schema.type == APIType.boolean);

    return documentedParameter;
  }
}

void _registerType(APIDocumentContext context, TypeMirror typeMirror) {
  if (typeMirror is! ClassMirror) {
    return;
  }

  final classMirror = typeMirror as ClassMirror;
  if (!context.schema.hasRegisteredType(classMirror.reflectedType) &&
      _shouldDocumentSerializable(classMirror.reflectedType)) {
    final instance =
        classMirror.newInstance(const Symbol(''), []).reflectee as Serializable;
    context.schema.register(MirrorSystem.getName(classMirror.simpleName),
        instance.documentSchema(context),
        representation: classMirror.reflectedType);
  }
}

bool _shouldDocumentSerializable(Type type) {
  final hierarchy = classHierarchyForClass(reflectClass(type));
  final definingType = hierarchy.firstWhere(
      (cm) => cm.staticMembers.containsKey(#shouldAutomaticallyDocument),
      orElse: () => null);
  if (definingType == null) {
    return Serializable.shouldAutomaticallyDocument;
  }
  return definingType.getField(#shouldAutomaticallyDocument).reflectee as bool;
}
