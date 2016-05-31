part of aqueduct;

class ResourceController<T extends Model> extends HttpController {
  ResourceController([ModelContext context]) : super() {
    _query = new ModelQuery<T>(context: context ?? ModelContext.defaultContext);
  }

  ModelQuery<T> _query;

  Future<ModelQuery<T>> willExecuteQuery(ModelQuery<T> query) async {
    return query;
  }

  Future<dynamic> didExecuteQueryWithResult(ModelQuery<T> executedQuery, List<T> results) async {
    return results;
  }

  @httpGet getOne(String id) async {
    _query[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    _query = await willExecuteQuery(_query);

    var results = await _query.fetchOne();

  }

  dynamic _parsePrimaryKey(String id) {
    var primaryKey = _query.entity.primaryKey;
    var primaryAttribute = _query.entity.attributes[primaryKey];

    switch (primaryAttribute.type) {
      case PropertyType.string: return id;
      case PropertyType.bigInteger: return int.parse(id);
      case PropertyType.integer: return int.parse(id);
      case PropertyType.datetime: return DateTime.parse(id);
      case PropertyType.doublePrecision: return double.parse(id);
      case PropertyType.boolean: return id == "true";
    }

    throw new QueryException(404, "Unknown primary key", -1);
  }
}