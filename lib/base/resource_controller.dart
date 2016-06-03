part of aqueduct;

class ResourceController<ModelType extends Model> extends HttpController {
  ResourceController([ModelContext context]) : super() {
    _query = new ModelQuery<ModelType>(context: context ?? ModelContext.defaultContext);
  }

  ModelQuery<ModelType> _query;

  Future<ModelQuery<ModelType>> willFindObjectWithQuery(ModelQuery<ModelType> query) async {
    return query;
  }

  Future<Response> didFindObject(ModelType result) async {
    return new Response.ok(result);
  }

  Future<Response> didNotFindObject() async {
    return new Response.notFound();
  }

  @httpGet getObject(String id) async {
    _query[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    _query = await willFindObjectWithQuery(_query);

    var result = await _query.fetchOne();
    if (result == null) {
      return await didNotFindObject();
    } else {
      return await didFindObject(result);
    }
  }

  Future<ModelQuery<ModelType>> willInsertObjectWithQuery(ModelQuery<ModelType> query) async {
    return query;
  }

  Future<Response> didInsertObject(ModelType object) async {
    return new Response.ok(object);
  }

  @httpPost createObject() async {
    ModelType instance = _query.entity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
    instance.readMap(requestBody);
    _query.values = instance;

    _query = await willInsertObjectWithQuery(_query);
    var result = await _query.insert();

    return await didInsertObject(result);
  }

  Future<ModelQuery<ModelType>> willDeleteObjectWithQuery(ModelQuery<ModelType> query) async {
    return query;
  }

  Future<Response> didDeleteObjectWithID(dynamic id) async {
    return new Response.ok(null);
  }

  Future<Response> didNotFindObjectToDeleteWithID(dynamic id) async {
    return new Response.notFound();
  }

  @httpDelete deleteObject(String id) async {
    _query[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    _query = await willDeleteObjectWithQuery(_query);

    var result = await _query.delete();

    if (result == 0) {
      return await didNotFindObjectToDeleteWithID(id);
    } else {
      return await didDeleteObjectWithID(id);
    }
  }

  Future<ModelQuery<ModelType>> willUpdateObjectWithQuery(ModelQuery<ModelType> query) async {
    return query;
  }

  Future<Response> didUpdateObject(ModelType object) async {
    return new Response.ok(object);
  }

  Future<Response> didNotFindObjectToUpdateWithID(dynamic id) async {
    return new Response.notFound();
  }

  @httpPut updateObject(String id) async {
    _query[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    ModelType instance = _query.entity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
    instance.readMap(requestBody);
    _query.values = instance;

    _query = await willUpdateObjectWithQuery(_query);
    var results = await _query.update();
    if (results.length == 0) {
      return await didNotFindObjectToDeleteWithID(id);
    } else {
      return didUpdateObject(results.first);
    }
  }

  Future<ModelQuery<ModelType>> willFindObjectsWithQuery(ModelQuery<ModelType> query) async {
    return query;
  }

  Future<Response> didFindObjects(List<ModelType> objects) async {
    return new Response.ok(objects);
  }

  @httpGet getObjects({int count: 0, int offset: 0, String pageBy: null, String pageAfter: null, String pagePrior: null, List<String> sortBy: null}) async {
    _query.fetchLimit = count;
    _query.offset = offset;

    if (pageBy != null) {
      var direction = null;
      var pageValue = null;
      if (pageAfter != null) {
        direction = PageDirection.after;
        pageValue = pageAfter;
      } else if (pagePrior != null) {
        direction = PageDirection.prior;
        pageValue = pagePrior;
      } else {
        return new Response.badRequest(body: {"error" : "If defining pageBy, either pageAfter or pagePrior must be defined. 'null' is a valid value"});
      }

      if (_query.entity.properties[pageBy] == null) {
        throw new HttpResponseException(400, "pageBy key ${pageBy} does not exist for ${_query.entity.tableName}");
      }

      _query.pageDescriptor = new QueryPage(direction, pageBy, pageValue == "null" ? null : pageValue);
    }

    if (sortBy != null) {
      _query.sortDescriptors = sortBy.map((sort) {
        var split = sort.split(",").map((str) => str.trim()).toList();
        if (split.length != 2) {
          throw new HttpResponseException(500, "sortBy keys must be string pairs delimited by a comma: key,asc or key,desc");
        }
        if (_query.entity.properties[split.first] == null) {
          throw new HttpResponseException(400, "sortBy key ${split.first} does not exist for ${_query.entity.tableName}");
        }
        if (split.last != "asc" && split.last != "desc") {
          throw new HttpResponseException(400, "sortBy order must be either asc or desc, not ${split.last}");
        }
        return new SortDescriptor(split.first, split.last == "asc" ? SortDescriptorOrder.ascending : SortDescriptorOrder.descending);
      }).toList();
    }

    var results = await _query.fetch();

    return await didFindObjects(results);
  }

  dynamic _parsePrimaryKey(String id) {
    var primaryKey = _query.entity.primaryKey;
    var primaryAttribute = _query.entity.attributes[primaryKey];

    try {
      switch (primaryAttribute.type) {
        case PropertyType.string: return id;
        case PropertyType.bigInteger: return int.parse(id);
        case PropertyType.integer: return int.parse(id);
        case PropertyType.datetime: return DateTime.parse(id);
        case PropertyType.doublePrecision: return double.parse(id);
        case PropertyType.boolean: return id == "true";
      }
    } on FormatException {
      throw new QueryException(404, "Unknown primary key", -1);
    }

    return null;
  }
}