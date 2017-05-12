import 'dart:async';

import '../db/db.dart';
import 'http.dart';

/// A partial class for implementing an [HTTPController] that has a few conveniences
/// for executing [Query]s.
///
/// Instances of [QueryController] are [HTTPController]s that have a pre-baked [Query] available. This [Query]'s type -
/// the [ManagedObject] type is operates on - is defined by [InstanceType].
///
/// The values of [query] are set based on the HTTP method, HTTP path and request body.
/// Prior to executing a responder method in subclasses of [QueryController], the [query]
/// will have the following attributes under the following conditions:
///
/// 1. The [Query] will always have a type argument that matches [InstanceType].
/// 2. If the request contains a path variable that matches the name of the primary key of [InstanceType], the [Query] will set
/// its [Query.where] to match on the [ManagedObject] whose primary key is that value of the path parameter.
/// 3. If the [Request] contains a body, it will be decoded per the [acceptedContentTypes] and deserialized into the [query]'s [values] property via [readMap].
abstract class QueryController<InstanceType extends ManagedObject>
    extends HTTPController {
  /// Create an instance of [QueryController]. By default, [context] is the [ManagedContext.defaultContext].
  QueryController([ManagedContext context]) : super() {
    query = new Query<InstanceType>(context ?? ManagedContext.defaultContext);
  }

  /// A query representing the values received from the [request] being processed.
  ///
  /// You may execute this [query] as is or modify it. The following is true of this property:
  ///
  /// 1. The [Query] will always have a type argument that matches [InstanceType].
  /// 2. If the request contains a path variable that matches the name of the primary key of [InstanceType], the [Query] will set
  /// its [Query.where] to match on the [ManagedObject] whose primary key is that value of the path parameter.
  /// 3. If the [Request] contains a body, it will be decoded per the [acceptedContentTypes] and deserialized into the [query]'s [values] property via [readMap].
  Query<InstanceType> query;

  @override
  Future<RequestOrResponse> willProcessRequest(Request req) async {
    if (req.path.orderedVariableNames.length > 0) {
      var firstVarName = req.path.orderedVariableNames.first;
      var idValue = req.path.variables[firstVarName];

      if (idValue != null) {
        var primaryKeyDesc = query.entity.attributes[query.entity.primaryKey];
        if (primaryKeyDesc.isAssignableWith(idValue)) {
          query.where[query.entity.primaryKey] = idValue;
        } else if (primaryKeyDesc.type == ManagedPropertyType.bigInteger ||
            primaryKeyDesc.type == ManagedPropertyType.integer) {
          try {
            query.where[query.entity.primaryKey] = int.parse(idValue);
          } on FormatException {            
            return new Response.notFound();
          }
        } else {
          return new Response.notFound();
        }
      }
    }

    return super.willProcessRequest(req);
  }

  @override
  void didDecodeRequestBody(HTTPRequestBody body) {
    if (body.hasBody) {
      query.values.readMap(body.asMap());
      query.values.removePropertyFromBackingMap(query.values.entity.primaryKey);
    }
  }
}
