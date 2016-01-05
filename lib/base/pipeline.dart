part of monadart;

/// A abstract class that concrete subclasses will implement to provide request handling behavior.
///
/// [Application]s set up HTTP(S) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [ApplicationPipeline]. Instances of this class must implement the
/// [handleRequest] method from [RequestHandler] - this is the entry point of all requests into this pipeline.
abstract class ApplicationPipeline extends RequestHandler {

  /// Default constructor.
  ///
  /// The default constructor takes a [Map] of configuration [options]. The constructor should initialize
  /// properties that will be used throughout the callbacks executed during initialization. For any code that requires async initialization,
  /// use [willOpen]. However, it is important to note that any properties that are used during initialization callbacks (like [addRoutes]) should be
  /// initialized in this constructor and not during [willOpen]. If properties that are needed during initialization callbacks
  /// must be initialized asynchronously, those properties should implement their own deferred initialization mechanism
  /// that can be triggered in [willOpen], but still must be initialized in this constructor.
  ApplicationPipeline(this.options);

  /// This pipeline's router.
  ///
  /// The default router for a pipeline. Configure [router] by adding routes to it in [addRoutes].
  /// Using a router other than this router will impede the pipeline's ability to generate documentation.
  Router router = new Router();

  /// Configuration options for the application.
  ///
  /// Options allow passing of application-specific information - like database connection information -
  /// from configuration data. This property is set in the constructor.
  Map<String, dynamic> options;

  /// Returns the first handler in the pipeline.
  ///
  /// When a [ResourceRequest] is delivered to the pipeline, this
  /// handler will be the first to act on it.  By default, this is [router].
  RequestHandler initialHandler() {
    return router;
  }

  /// Callback for implementing this pipeline's routing table.
  ///
  /// Routes should only be added in this method to this instance's [router]. This method will execute prior to [willOpen] being called,
  /// so any properties this pipeline needs to handle route setup must be set in this instance's constructor.
  void addRoutes();

  /// Callback executed prior to this pipeline receiving requests.
  ///
  /// This method allows the pipeline to perform any asynchronous initialization prior to
  /// receiving requests. The pipeline will not open until the [Future] returned from this method completes.
  Future willOpen() {
    return null;
  }

  /// Executed after the pipeline is attached to an [HttpServer].
  ///
  /// This method is executed after the [HttpServer] is started and
  /// the [initialHandler] has been set to start receiving requests.
  /// Because requests could potentially be queued prior to this pipeline
  /// being opened, a request could be received prior to this method being executed.
  void didOpen() {}

  /// Executed for each [ResourceRequest] that will be sent to this pipeline.
  ///
  /// This method will run prior to each request being [deliver]ed to this
  /// pipeline's [initialHandler]. Use this method to provide additional
  /// context to the request prior to it being handled.
  Future willReceiveRequest(ResourceRequest request) async {

  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    return initialHandler().document(resolver);
  }
}