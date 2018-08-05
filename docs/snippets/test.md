# Aqueduct Test Snippets

## Expect that Response Returns a JSON Object with an ID

```dart
test("that Response Returns a JSON Object", () async {
  expectResponse(
    await app.client.request("/endpoint").get(),
    200, body: {
      "id": isNumber
    }
  );
});
```

## Expect that Response Returns a List of JSON Objects with IDs

```dart
test("that Response returns a list of JSON Objects with IDs", () async {
  expectResponse(
    await app.client.request("/endpoint").get(),
    200, body: everyElement({
      "id": isNumber
    })
  );
});
```

## Expect that Last-Modified Header Is After Date

```dart
test("that Last-Modified Header Is After Date ", () async {
  expect(
    await app.client.request("/endpoint").get(),
    hasHeaders({
      "last-modified": isAfter(new DateTime(2017))
    });
});
```

## HTTP POST with JSON in Test 

```dart
test("that can send JSON body", () async {
  var request = app.client.request("/endpoint")
    ..json = {
      "id": 1
    };
  expect(await request.post(), hasStatus(202));
});
```
