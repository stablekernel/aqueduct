part of aqueduct;

class ModelController<T extends Model> extends HttpController {
  ModelController([ModelContext context]) : super() {
    query = new ModelQuery<T>(context: context ?? ModelContext.defaultContext);
  }

  ModelQuery<T> query;

  @override
  Future<RequestHandlerResult> willProcessRequest(Request req) async {
    var firstVarName = req.path.firstVariableName;

    if (firstVarName != null) {
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
  void didDecodeRequestBody(Map <String, dynamic> bodyMap) {
    var reflectedModel = reflectClass(T).newInstance(new Symbol(""), []);
    query.values = reflectedModel.reflectee;
    query.values.readMap(bodyMap);

    query.values.dynamicBacking.remove(query.values.entity.primaryKey);
  }
}