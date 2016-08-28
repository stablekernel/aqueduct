part of aqueduct;

/// A partial class for implementing an [HTTPController] that has a few conveniences
/// for handling [Model] objects.
///
/// Intended to be subclassed. Instances of [ModelController] are [HTTPController]s whose
/// type argument indicates the type of [Model] object they are responsible for executing [Query]s
/// on. [ModelController]s expose a [query] property that is pre-populated with data from the incoming [Request].
///
/// Prior to executing a handler method in subclasses of [ModelController], the [query]
/// will have the following attributes under the following conditions:
///
/// 1. The Query will always have a type argument that matches [T].
/// 2. If the request contains a path variable, the first path variable (reading from left to right) will be used to as a matcher
/// on the entity's primary key. For example, a [Request] with the path /users/:id and a type argument of User (whose primary key is userID) will generate a Query as though:
///
///         query = new ModelQuery<User>()..userID = whereEqualTo(req.path["id"]);
///
/// 3. If the [Request] contains a body, it will be decoded per the [acceptedContentTypes] and deserialized into the [query]'s [values] property via [readMap].
abstract class ModelController<T extends Model> extends HTTPController {

  /// Create an instance of [ModelController]. By default, [context] is the [defaultContext].
  ModelController([ModelContext context]) : super() {
    query = new ModelQuery<T>(context: context ?? ModelContext.defaultContext);
  }

  /// A query representing the values received from the [request] being processed.
  ///
  /// You may execute this [query] as is or modify it.
  ModelQuery<T> query;

  @override
  Future<RequestHandlerResult> willProcessRequest(Request req) async {
    if (req.path.orderedVariableNames.length > 0) {
      var firstVarName = req.path.orderedVariableNames.first;
      var idValue = req.path.variables[firstVarName];

      if (idValue != null) {
        var primaryKeyDesc = query.entity.attributes[query.entity.primaryKey];
        if (primaryKeyDesc.isAssignableWith(idValue)) {
          query[query.entity.primaryKey] = idValue;
        } else if (primaryKeyDesc.type == PropertyType.bigInteger || primaryKeyDesc.type == PropertyType.integer) {
          try {
            query[query.entity.primaryKey] = int.parse(idValue);
          } on FormatException {
            var errorMessage = "Expected integer value for ModelController on ${query.entity}, but $idValue was not able to be parsed to an integer.";
            logger.info(errorMessage);

            return new Response.notFound(body: {"error" : errorMessage});
          }
        } else {
          var errorMessage = "ID Value $idValue is not assignable for ModelController on ${query.entity}, expected value of type ${primaryKeyDesc.type}";
          logger.info(errorMessage);

          return new Response.notFound(body: {"error" : errorMessage});
        }
      }
    }

    return super.willProcessRequest(req);
  }

  @override
  void didDecodeRequestBody(dynamic body) {
    var bodyMap = body as Map<String, dynamic>;
    var reflectedModel = reflectClass(T).newInstance(new Symbol(""), []);
    query.values = reflectedModel.reflectee as T;
    query.values.readMap(bodyMap);

    query.values.dynamicBacking.remove(query.values.entity.primaryKey);
  }
}