# Uploading Files

Files are often uploaded as part of a multipart form request. A request of this type has the content-type `multipart/form-data` and is body is made up of multiple data *parts*. These segments are typically the base64 encoded contents of a file and accompanying metadata for the upload.

Multipart data is decoded using objects from `package:mime`. You must add this package your application's `pubspec.yaml` file:

```yaml
dependencies:
  mime: any # prefer a better constraint than this
```

By default, resource controllers only accept `application/json` requests and must be configured to accept `multipart/form-data` requests. To read each part, create a `MimeMultipartTransformer` and stream the body into it. The following shows an example:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:mime/mime.dart';

class MyController extends ResourceController {
  MyController() {
    acceptedContentTypes = [ContentType("multipart", "form-data")];
  }

  @Operation.post()
  Future<Response> postForm() async {}
    final boundary = request.raw.headers.contentType.parameters["boundary"];
    final transformer = MimeMultipartTransformer(boundary);
    final bodyBytes = await request.body.decode<List<int>>();

    // Pay special attention to the square brackets in the argument:
    final bodyStream = Stream.fromIterable([bodyBytes]);
    final parts = await transformer.bind(bodyStream).toList();

    for (var part in parts) {
      final headers = part.headers;
      final content = await part.toList();

      // Use headers['content-disposition'] to identify the part
      // The byte content of the part is available in 'content'.
    }    
  }
}
```
