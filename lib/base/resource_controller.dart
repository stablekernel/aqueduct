part of aqueduct;

/// A [RequestHandler] for performing CRUD operations on [Model] instances.
///
/// Instances of this class create and execute [Query]s based on [Request]'s they receive. This instances of this class effectively map a REST API call
/// directly to the database. For example, this [RequestHandler] handles an HTTP PUT request by executing an update [Query]; the path variable in the request
/// indicates the value of the primary key for the updated row and the HTTP request body are the values updated.
///
/// When routing to a [ResourceController], you must provide the following route pattern, where <name> can be any string:
///
///       router.route("/<name>/[:id]")
///
/// You may optionally use the static method [routePattern] to create this string for you.
///
/// The mapping for HTTP request to action is as follows:
///
///       GET /<name>/:id -> Fetch Object by ID
///       PUT /<name>/:id -> Update Object by ID, HTTP Request Body contains update values.
///       DELETE /<name>/:id -> Delete Object by ID
///       POST /<name> -> Create new Object, HTTP Request Body contains update values.
///       GET /<name> -> Fetch instances of Object
///
/// You may use this class without subclassing, but you may also subclass it to modify the executed [Query] prior to its execution or the returned [Response] based
/// on the [Query]'s results.
///
/// The HTTP response body is encoded according to [responseContentType].
///
/// GET requests with no path parameter can take extra query parameters to modify the request. The following are the available query parameters:
///
///       count (integer): restricts the number of objects fetched to count. By default, this is null, which means no restrictions.
///       offset (integer): offsets the fetch by offset amount of objects. By default, this is null, which means no offset.
///       pageBy (string): indicates the key in which to page by. See [QueryPage] for more information on paging. If this value is passed as part of the query, either pageAfter or pagePrior must also be passed, but only one of those.
///       pageAfter (string): indicates the page value and direction of the paging. pageBy must also be set. See [QueryPage] for more information.
///       pagePrior (string): indicates the page value and direction of the paging. pageBy must also be set. See [QueryPage] for more information.
///       sortBy (string): indicates the sort order. The syntax is 'sortBy=key,order' where key is a property of [InstanceType] and order is either 'asc' or 'desc'. You may specify multiple sortBy parameters.
///
class ResourceController<InstanceType extends Model> extends HTTPController {
  /// Returns a route pattern for using [ResourceController]s.
  ///
  /// Returns the string "/$name/[:id]", to be used as a route pattern in a [Router] for instances of [ResourceController] and subclasses.
  static String routePattern(String name) {
    return "/$name/[:id]";
  }

  /// Creates an instance of a [ResourceController].
  ///
  /// [context] defaults to [defaultContext].
  ResourceController([ModelContext context]) : super() {
    _query = new Query<InstanceType>(context: context ?? ModelContext.defaultContext);
  }

  Query<InstanceType> _query;

  /// Executed prior to a fetch by ID query.
  ///
  /// You may modify the [query] prior to its execution in this method. The [query] will have a single matcher, where the [InstanceType]'s primary key
  /// is equal to the first path argument in the [Request]. You may also return a new [Query],
  /// but it must have the same [InstanceType] as this controller. If you return null from this method, no [Query] will be executed
  /// and [didNotFindObject] will immediately be called.
  Future<Query<InstanceType>> willFindObjectWithQuery(Query<InstanceType> query) async {
    return query;
  }

  /// Executed after a fetch by ID query that found a matching instance.
  ///
  /// By default, returns a [Response.ok] with the encoded instance. The [result] is the fetched [InstanceType]. You may override this method
  /// to provide some other behavior.
  Future<Response> didFindObject(InstanceType result) async {
    return new Response.ok(result);
  }

  /// Executed after a fetch by ID query that did not find a matching instance.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  Future<Response> didNotFindObject() async {
    return new Response.notFound();
  }

  @httpGet getObject(String id) async {
    _query.matchOn[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    _query = await willFindObjectWithQuery(_query);

    var result = await _query?.fetchOne();

    if (result == null) {
      return await didNotFindObject();
    } else {
      return await didFindObject(result);
    }
  }

  /// Executed prior to an insert query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didInsertObject] will immediately be called with the value null.
  Future<Query<InstanceType>> willInsertObjectWithQuery(Query<InstanceType> query) async {
    return query;
  }

  /// Executed after an insert query is successful.
  ///
  /// By default, returns [Response.ok]. The [object] is the newly inserted [InstanceType]. You may override this method to provide some other behavior.
  Future<Response> didInsertObject(InstanceType object) async {
    return new Response.ok(object);
  }

  @httpPost createObject() async {
    InstanceType instance = _query.entity.instanceType.newInstance(new Symbol(""), []).reflectee as InstanceType;
    instance.readMap(requestBody as Map<String, dynamic>);
    _query.values = instance;

    _query = await willInsertObjectWithQuery(_query);
    var result = await _query?.insert();

    return await didInsertObject(result);
  }

  /// Executed prior to a delete query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no delete operation will be performed and [didNotFindObjectToDeleteWithID] will immediately be called with the value null.
  Future<Query<InstanceType>> willDeleteObjectWithQuery(Query<InstanceType> query) async {
    return query;
  }

  /// Executed after an object was deleted.
  ///
  /// By default, returns [Response.ok] with no response body. You may override this method to provide some other behavior.
  Future<Response> didDeleteObjectWithID(dynamic id) async {
    return new Response.ok(null);
  }

  /// Executed when no object was deleted during a delete query.
  ///
  /// Defaults to return [Response.notFound]. You may override this method to provide some other behavior.
  Future<Response> didNotFindObjectToDeleteWithID(dynamic id) async {
    return new Response.notFound();
  }

  @httpDelete deleteObject(String id) async {
    _query.matchOn[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    _query = await willDeleteObjectWithQuery(_query);

    var result = await _query?.delete();

    if (result == 0) {
      return await didNotFindObjectToDeleteWithID(id);
    } else {
      return await didDeleteObjectWithID(id);
    }
  }

  /// Executed prior to a update query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didNotFindObjectToUpdateWithID] will immediately be called with the value null.
  Future<Query<InstanceType>> willUpdateObjectWithQuery(Query<InstanceType> query) async {
    return query;
  }

  /// Executed after an object was updated.
  ///
  /// By default, returns [Response.ok] with the encoded, updated object. You may override this method to provide some other behavior.
  Future<Response> didUpdateObject(InstanceType object) async {
    return new Response.ok(object);
  }

  /// Executed after an object not found during an update query.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  Future<Response> didNotFindObjectToUpdateWithID(dynamic id) async {
    return new Response.notFound();
  }

  @httpPut updateObject(String id) async {
    _query.matchOn[_query.entity.primaryKey] = whereEqualTo(_parsePrimaryKey(id));

    InstanceType instance = _query.entity.instanceType.newInstance(new Symbol(""), []).reflectee as InstanceType;
    instance.readMap(requestBody as Map<String, dynamic>);
    _query.values = instance;

    _query = await willUpdateObjectWithQuery(_query);

    var results = await _query?.updateOne();
    if (results == null) {
      return await didNotFindObjectToDeleteWithID(id);
    } else {
      return didUpdateObject(results);
    }
  }

  /// Executed prior to a fetch query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no objects will be fetched and [didFindObjects] will immediately be called with the value null.
  Future<Query<InstanceType>> willFindObjectsWithQuery(Query<InstanceType> query) async {
    return query;
  }

  /// Executed after a list of objects has been fetched.
  ///
  /// By default, returns [Response.ok] with the encoded list of founds objects (which may be the empty list).
  Future<Response> didFindObjects(List<InstanceType> objects) async {
    return new Response.ok(objects);
  }

  @httpGet getObjects({
    @HTTPQuery.optional("count") int count: 0,
    @HTTPQuery.optional("offset") int offset: 0,
    @HTTPQuery.optional("pageBy") String pageBy: null,
    @HTTPQuery.optional("pageAfter") String pageAfter: null,
    @HTTPQuery.optional("pagePrior") String pagePrior: null,
    @HTTPQuery.optional("sortBy") List<String> sortBy: null
  }) async {
    _query.fetchLimit = count;
    _query.offset = offset;

    if (pageBy != null) {
      var direction = null;
      var pageValue = null;
      if (pageAfter != null) {
        direction = SortOrder.ascending;
        pageValue = pageAfter;
      } else if (pagePrior != null) {
        direction = SortOrder.descending;
        pageValue = pagePrior;
      } else {
        return new Response.badRequest(body: {"error" : "If defining pageBy, either pageAfter or pagePrior must be defined. 'null' is a valid value"});
      }

      if (_query.entity.properties[pageBy] == null) {
        throw new HTTPResponseException(400, "pageBy key ${pageBy} does not exist for ${_query.entity.tableName}");
      }

      _query.pageDescriptor = new QueryPage(direction, pageBy, boundingValue: pageValue == "null" ? null : pageValue);
    }

    if (sortBy != null) {
      _query.sortDescriptors = sortBy.map((sort) {
        var split = sort.split(",").map((str) => str.trim()).toList();
        if (split.length != 2) {
          throw new HTTPResponseException(500, "sortBy keys must be string pairs delimited by a comma: key,asc or key,desc");
        }
        if (_query.entity.properties[split.first] == null) {
          throw new HTTPResponseException(400, "sortBy key ${split.first} does not exist for ${_query.entity.tableName}");
        }
        if (split.last != "asc" && split.last != "desc") {
          throw new HTTPResponseException(400, "sortBy order must be either asc or desc, not ${split.last}");
        }
        return new SortDescriptor(split.first, split.last == "asc" ? SortOrder.ascending : SortOrder.descending);
      }).toList();
    }

    _query = await willFindObjectsWithQuery(_query);

    var results = await _query?.fetch();

    return await didFindObjects(results);
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    var responses = super.documentResponsesForOperation(operation);
    if(operation.id == APIOperation.idForMethod(this, #getObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ModelContext.defaultContext.entityForType(InstanceType).documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "error" : new APISchemaObject.string()
            }
          ),
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #createObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ModelContext.defaultContext
              .entityForType(InstanceType)
              .documentedResponseSchema,
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #updateObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ModelContext.defaultContext.entityForType(InstanceType).documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "error" : new APISchemaObject.string()
            }
          ),
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #deleteObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ModelContext.defaultContext.entityForType(InstanceType).documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "error" : new APISchemaObject.string()
            }
          ),
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #getObjects)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeArray
            ..items = ModelContext.defaultContext.entityForType(InstanceType).documentedResponseSchema
          ),
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObjectTypeObject
            ..properties = {
              "error" : new APISchemaObject.string()
            }
          ),
      ]);
    }

    return responses;
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
        case PropertyType.transientList: return null;
        case PropertyType.transientMap: return null;
      }
    } on FormatException {
      throw new HTTPResponseException(404, "Unknown primary key");
    }

    return null;
  }
}