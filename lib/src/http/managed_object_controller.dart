import 'dart:async';
import 'dart:io';

import '../db/db.dart';
import 'http.dart';

/// A [Controller] that implements basic CRUD operations for a [ManagedObject].
///
/// Instances of this class map a REST API call
/// directly to a database [Query]. For example, this [Controller] handles an HTTP PUT request by executing an update [Query]; the path variable in the request
/// indicates the value of the primary key for the updated row and the HTTP request body are the values updated.
///
/// When routing to a [ManagedObjectController], you must provide the following route pattern, where <name> can be any string:
///
///       router.route("/<name>/[:id]")
///
/// You may optionally use the static method [ManagedObjectController.routePattern] to create this string for you.
///
/// The mapping for HTTP request to action is as follows:
///
/// - GET /<name>/:id -> Fetch Object by ID
/// - PUT /<name>/:id -> Update Object by ID, HTTP Request Body contains update values.
/// - DELETE /<name>/:id -> Delete Object by ID
/// - POST /<name> -> Create new Object, HTTP Request Body contains update values.
/// - GET /<name> -> Fetch instances of Object
///
/// You may use this class without subclassing, but you may also subclass it to modify the executed [Query] prior to its execution, or modify the returned [Response] after the query has been completed.
///
/// The HTTP response body is encoded according to [responseContentType].
///
/// GET requests with no path parameter can take extra query parameters to modify the request. The following are the available query parameters:
///
/// - count (integer): restricts the number of objects fetched to count. By default, this is null, which means no restrictions.
/// - offset (integer): offsets the fetch by offset amount of objects. By default, this is null, which means no offset.
/// - pageBy (string): indicates the key in which to page by. See [Query.pageBy] for more information on paging. If this value is passed as part of the query, either pageAfter or pagePrior must also be passed, but only one of those.
/// - pageAfter (string): indicates the page value and direction of the paging. pageBy must also be set. See [Query.pageBy] for more information.
/// - pagePrior (string): indicates the page value and direction of the paging. pageBy must also be set. See [Query.pageBy] for more information.
/// - sortBy (string): indicates the sort order. The syntax is 'sortBy=key,order' where key is a property of [InstanceType] and order is either 'asc' or 'desc'. You may specify multiple sortBy parameters.
class ManagedObjectController<InstanceType extends ManagedObject>
    extends RESTController {
  /// Creates an instance of a [ManagedObjectController].
  ///
  /// [context] defaults to [ManagedContext.defaultContext].
  ManagedObjectController([ManagedContext context]) : super() {
    _query = new Query<InstanceType>(context ?? ManagedContext.defaultContext);
  }

  /// Creates a new [ManagedObjectController] without a static type.
  ///
  /// This method is used when generating instances of this type dynamically from runtime values,
  /// where the static type argument cannot be defined. Behaves just like the unnamed constructor.
  ///
  ManagedObjectController.forEntity(
      ManagedEntity entity, [ManagedContext context]) : super() {
    _query = new Query.forEntity(entity, context ?? ManagedContext.defaultContext);
  }

  /// Returns a route pattern for using [ManagedObjectController]s.
  ///
  /// Returns the string "/$name/[:id]", to be used as a route pattern in a [Router] for instances of [ResourceController] and subclasses.
  static String routePattern(String name) {
    return "/$name/[:id]";
  }

  Query<InstanceType> _query;

  /// Executed prior to a fetch by ID query.
  ///
  /// You may modify the [query] prior to its execution in this method. The [query] will have a single matcher, where the [InstanceType]'s primary key
  /// is equal to the first path argument in the [Request]. You may also return a new [Query],
  /// but it must have the same [InstanceType] as this controller. If you return null from this method, no [Query] will be executed
  /// and [didNotFindObject] will immediately be called.
  FutureOr<Query<InstanceType>> willFindObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after a fetch by ID query that found a matching instance.
  ///
  /// By default, returns a [Response.ok] with the encoded instance. The [result] is the fetched [InstanceType]. You may override this method
  /// to provide some other behavior.
  FutureOr<Response> didFindObject(InstanceType result) {
    return new Response.ok(result);
  }

  /// Executed after a fetch by ID query that did not find a matching instance.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObject() {
    return new Response.notFound();
  }

  @Bind.get()
  Future<Response> getObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    _query.where[primaryKey] = whereEqualTo(
        _parseValueForProperty(id, _query.entity.properties[primaryKey]));

    _query = await willFindObjectWithQuery(_query);

    var result = await _query?.fetchOne();

    if (result == null) {
      return didNotFindObject();
    } else {
      return didFindObject(result);
    }
  }

  /// Executed prior to an insert query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didInsertObject] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willInsertObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an insert query is successful.
  ///
  /// By default, returns [Response.ok]. The [object] is the newly inserted [InstanceType]. You may override this method to provide some other behavior.
  FutureOr<Response> didInsertObject(InstanceType object) {
    return new Response.ok(object);
  }

  @Bind.post()
  Future<Response> createObject() async {
    InstanceType instance = _query.entity.instanceType
        .newInstance(new Symbol(""), []).reflectee as InstanceType;
    instance.readFromMap(request.body.asMap());
    _query.values = instance;

    _query = await willInsertObjectWithQuery(_query);
    var result = await _query?.insert();

    return didInsertObject(result);
  }

  /// Executed prior to a delete query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no delete operation will be performed and [didNotFindObjectToDeleteWithID] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willDeleteObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an object was deleted.
  ///
  /// By default, returns [Response.ok] with no response body. You may override this method to provide some other behavior.
  FutureOr<Response> didDeleteObjectWithID(dynamic id) {
    return new Response.ok(null);
  }

  /// Executed when no object was deleted during a delete query.
  ///
  /// Defaults to return [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObjectToDeleteWithID(dynamic id) {
    return new Response.notFound();
  }

  @Bind.delete()
  Future<Response> deleteObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    _query.where[primaryKey] = whereEqualTo(
        _parseValueForProperty(id, _query.entity.properties[primaryKey]));

    _query = await willDeleteObjectWithQuery(_query);

    var result = await _query?.delete();

    if (result == 0) {
      return didNotFindObjectToDeleteWithID(id);
    } else {
      return didDeleteObjectWithID(id);
    }
  }

  /// Executed prior to a update query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no values will be inserted and [didNotFindObjectToUpdateWithID] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willUpdateObjectWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after an object was updated.
  ///
  /// By default, returns [Response.ok] with the encoded, updated object. You may override this method to provide some other behavior.
  FutureOr<Response> didUpdateObject(InstanceType object) {
    return new Response.ok(object);
  }

  /// Executed after an object not found during an update query.
  ///
  /// By default, returns [Response.notFound]. You may override this method to provide some other behavior.
  FutureOr<Response> didNotFindObjectToUpdateWithID(dynamic id) {
    return new Response.notFound();
  }

  @Bind.put()
  Future<Response> updateObject(@Bind.path("id") String id) async {
    var primaryKey = _query.entity.primaryKey;
    _query.where[primaryKey] = whereEqualTo(
        _parseValueForProperty(id, _query.entity.properties[primaryKey]));

    InstanceType instance = _query.entity.instanceType
        .newInstance(new Symbol(""), []).reflectee as InstanceType;
    instance.readFromMap(request.body.asMap());
    _query.values = instance;

    _query = await willUpdateObjectWithQuery(_query);

    var results = await _query?.updateOne();
    if (results == null) {
      return didNotFindObjectToUpdateWithID(id);
    } else {
      return didUpdateObject(results);
    }
  }

  /// Executed prior to a fetch query being executed.
  ///
  /// You may modify the [query] prior to its execution in this method. You may also return a new [Query],
  /// but it must have the same type argument as this controller. If you return null from this method,
  /// no objects will be fetched and [didFindObjects] will immediately be called with the value null.
  FutureOr<Query<InstanceType>> willFindObjectsWithQuery(
      Query<InstanceType> query) {
    return query;
  }

  /// Executed after a list of objects has been fetched.
  ///
  /// By default, returns [Response.ok] with the encoded list of founds objects (which may be the empty list).
  FutureOr<Response> didFindObjects(List<InstanceType> objects) {
    return new Response.ok(objects);
  }

  @Bind.get()
  Future<Response> getObjects(
      {@Bind.query("count") int count: 0,
      @Bind.query("offset") int offset: 0,
      @Bind.query("pageBy") String pageBy,
      @Bind.query("pageAfter") String pageAfter,
      @Bind.query("pagePrior") String pagePrior,
      @Bind.query("sortBy") List<String> sortBy}) async {
    _query.fetchLimit = count;
    _query.offset = offset;

    if (pageBy != null) {
      var direction;
      var pageValue;
      if (pageAfter != null) {
        direction = QuerySortOrder.ascending;
        pageValue = pageAfter;
      } else if (pagePrior != null) {
        direction = QuerySortOrder.descending;
        pageValue = pagePrior;
      } else {
        return new Response.badRequest(body: {
          "error":
              "If defining pageBy, either pageAfter or pagePrior must be defined. 'null' is a valid value"
        });
      }

      var pageByProperty = _query.entity.properties[pageBy];
      if (pageByProperty == null) {
        throw new HTTPResponseException(400,
            "pageBy key $pageBy does not exist for ${_query.entity.tableName}");
      }

      pageValue = _parseValueForProperty(pageValue, pageByProperty);
      _query.pageBy((t) => t[pageBy], direction,
          boundingValue: pageValue == "null" ? null : pageValue);
    }

    if (sortBy != null) {
      sortBy.forEach((sort) {
        var split = sort.split(",").map((str) => str.trim()).toList();
        if (split.length != 2) {
          throw new HTTPResponseException(400,
              "sortBy keys must be string pairs delimited by a comma: key,asc or key,desc");
        }
        if (_query.entity.properties[split.first] == null) {
          throw new HTTPResponseException(400,
              "sortBy key ${split.first} does not exist for ${_query.entity.tableName}");
        }
        if (split.last != "asc" && split.last != "desc") {
          throw new HTTPResponseException(400,
              "sortBy order must be either asc or desc, not ${split.last}");
        }
        var sortOrder = split.last == "asc"
            ? QuerySortOrder.ascending
            : QuerySortOrder.descending;
        _query.sortBy((t) => t[split.first], sortOrder);
      });
    }

    _query = await willFindObjectsWithQuery(_query);

    var results = await _query?.fetch();

    return didFindObjects(results);
  }

  @override
  APIRequestBody documentRequestBodyForOperation(APIOperation operation) {
    var req = new APIRequestBody()
      ..required = true
      ..description = "Request Body"
      ..schema = ManagedContext.defaultContext
          .entityForType(InstanceType)
          .documentedRequestSchema;

    if (operation.id ==
        APIOperation.idForMethod(this, #createObject)) {} else if (operation
            .id ==
        APIOperation.idForMethod(this, #updateObject)) {} else {
      return null;
    }

    return req;
  }

  @override
  List<APIResponse> documentResponsesForOperation(APIOperation operation) {
    var responses = super.documentResponsesForOperation(operation);
    if (operation.id == APIOperation.idForMethod(this, #getObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ManagedContext.defaultContext
              .entityForType(InstanceType)
              .documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #createObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ManagedContext.defaultContext
              .entityForType(InstanceType)
              .documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.CONFLICT
          ..description = "Object already exists"
          ..schema = new APISchemaObject(
              properties: {"error": new APISchemaObject.string()})
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #updateObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = ManagedContext.defaultContext
              .entityForType(InstanceType)
              .documentedResponseSchema,
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = "",
        new APIResponse()
          ..statusCode = HttpStatus.CONFLICT
          ..description = "Object already exists"
          ..schema = new APISchemaObject(
              properties: {"error": new APISchemaObject.string()})
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #deleteObject)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = "",
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
      ]);
    } else if (operation.id == APIOperation.idForMethod(this, #getObjects)) {
      responses.addAll([
        new APIResponse()
          ..statusCode = HttpStatus.OK
          ..description = ""
          ..schema = (new APISchemaObject()
            ..type = APISchemaObject.TypeArray
            ..items = ManagedContext.defaultContext
                .entityForType(InstanceType)
                .documentedResponseSchema),
        new APIResponse()
          ..statusCode = HttpStatus.NOT_FOUND
          ..description = ""
      ]);
    }

    return responses;
  }

  dynamic _parseValueForProperty(
      String value, ManagedPropertyDescription desc) {
    if (value == "null") {
      return null;
    }

    try {
      switch (desc.type) {
        case ManagedPropertyType.string:
          return value;
        case ManagedPropertyType.bigInteger:
          return int.parse(value);
        case ManagedPropertyType.integer:
          return int.parse(value);
        case ManagedPropertyType.datetime:
          return DateTime.parse(value);
        case ManagedPropertyType.doublePrecision:
          return double.parse(value);
        case ManagedPropertyType.boolean:
          return value == "true";
        case ManagedPropertyType.transientList:
          return null;
        case ManagedPropertyType.transientMap:
          return null;
      }
    } on FormatException {
      throw new HTTPResponseException(404, "Unknown primary key");
    }

    return null;
  }
}
