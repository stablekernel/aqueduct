import 'dart:async';

import '../db/db.dart';
import 'http.dart';

/// A partial class for implementing an [ResourceController] that has a few conveniences
/// for executing [Query]s.
///
/// Instances of [QueryController] are [ResourceController]s that have a pre-baked [Query] available. This [Query]'s type -
/// the [ManagedObject] type is operates on - is defined by [InstanceType].
///
/// The values of [query] are set based on the HTTP method, HTTP path and request body.
/// Prior to executing an operation method in subclasses of [QueryController], the [query]
/// will have the following attributes under the following conditions:
///
/// 1. The [Query] will always have a type argument that matches [InstanceType].
/// 2. If the request contains a path variable that matches the name of the primary key of [InstanceType], the [Query] will set
/// its [Query.where] to match on the [ManagedObject] whose primary key is that value of the path parameter.
/// 3. If the [Request] contains a body, it will be decoded per the [acceptedContentTypes] and deserialized into the [Query.values] property via [ManagedObject.readFromMap].
abstract class QueryController<InstanceType extends ManagedObject>
    extends ResourceController {
  /// Create an instance of [QueryController].
  QueryController(ManagedContext context) : super() {
    query = Query<InstanceType>(context);
  }

  /// A query representing the values received from the [request] being processed.
  ///
  /// You may execute this [query] as is or modify it. The following is true of this property:
  ///
  /// 1. The [Query] will always have a type argument that matches [InstanceType].
  /// 2. If the request contains a path variable that matches the name of the primary key of [InstanceType], the [Query] will set
  /// its [Query.where] to match on the [ManagedObject] whose primary key is that value of the path parameter.
  /// 3. If the [Request] contains a body, it will be decoded per the [acceptedContentTypes] and deserialized into the [Query.values] property via [ManagedObject.readFromMap].
  Query<InstanceType> query;

  @override
  FutureOr<RequestOrResponse> willProcessRequest(Request req) {
    if (req.path.orderedVariableNames.isNotEmpty) {
      var firstVarName = req.path.orderedVariableNames.first;
      var idValue = req.path.variables[firstVarName];

      if (idValue != null) {
        var primaryKeyDesc = query.entity.attributes[query.entity.primaryKey];
        if (primaryKeyDesc.isAssignableWith(idValue)) {
          query.where((o) => o[query.entity.primaryKey]).equalTo(idValue);
        } else if (primaryKeyDesc.type.kind == ManagedPropertyType.bigInteger ||
            primaryKeyDesc.type.kind == ManagedPropertyType.integer) {
          try {
            query
                .where((o) => o[query.entity.primaryKey])
                .equalTo(int.parse(idValue));
          } on FormatException {
            return Response.notFound();
          }
        } else {
          return Response.notFound();
        }
      }
    }

    return super.willProcessRequest(req);
  }

  @override
  void didDecodeRequestBody(RequestBody body) {
    query.values.readFromMap(body.as());
    query.values.removePropertyFromBackingMap(query.values.entity.primaryKey);
  }
}
