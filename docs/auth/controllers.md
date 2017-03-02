# Issue Access Tokens with AuthController

An application using Aqueduct's Auth framework must have endpoints to exchange credentials for access tokens. While a developer could implement these endpoints themselves and talk directly to an `AuthServer`, the OAuth 2.0 specification is where happiness goes to die. Therefore, there exists a `RequestController`s in Aqueduct that handles granting and refreshing authorization tokens named `AuthController` (the resource owner grant flow). Another controller, `AuthCodeController`, handles the authorization code flow.

### Issue, Refresh and Exchange Tokens with AuthController

Using an `AuthController` in an application is straightforward - hook it up to a `Router` and pass it an `AuthServer`.

```dart
@override
void setupRouter(Router router) {
  router
    .route("/auth/token")
    .generate(() => new AuthController(authServer));
}
```

An `AuthController` follows the OAuth 2.0 specification for granting and refreshing access tokens. To grant an access token, a client application sends a POST HTTP request to the controller. The request must contain two important components: an Authorization header with the Client ID and Client Secret, and a `x-www-form-urlencoded` body with the username and password of the authenticating user. The body must also contain the key-value pair `grant_type=password`. For example, the following Dart code will initiate successful authentication:

```dart
var clientID = ...;
var clientSecret = ...;

var body = {
  "username": "bob@stablekernel.com",
  "password": "foobar",
  "grant_type": "password"
};

// this creates a URL encoded version of: 'username=bob@stablekernel.com&password=foobar&grant_type=password'
var bodyForm = body.keys
  .map((key) => "$key=${Uri.encodeQueryComponent(body[key])}")
  .join("&");

var clientCredentials = new Base64Encoder().convert("$clientID:$clientSecret".codeUnits);

var response = await http.post(
  "https://stablekernel.com/auth/token",
  headers: {
    "Content-Type": "application/x-www-form-urlencoded",
    "Authorization": "Basic $clientCredentials"
  },
  body: bodyForm);
```

The response to a password token request is a JSON body that follows the OAuth 2.0 specification:

```
{
  "access_token": "..."
  "refresh_token": "...",
  "expires_in": 3600,
  "token_type": "bearer"
}
```

Tokens are refreshed through the same endpoint, but with a payload that contains the refresh token and `grant_type=refresh_token`.

```
grant_type=refresh_token&refresh_token=kjasdiuz9u3namnsd
```

See [Aqueduct Auth CLI](cli.md) for more details on creating OAuth 2.0 client identifier and secrets.

If an Aqueduct application is using scope, an additional `scope` parameter can contain a space-delimited list of requested authorization scope. Only allowed scopes are returned and granted, and if no scopes are allowed then the request fails. If scope is provided, granted scope will be available in the response body.

It is important that an `Authorizer` *does not* protect instances of `AuthController`. The Authorization header is parsed and verified by `AuthController`.

Once granted, an access token can be used to pass `Authorizer`s in protected endpoints.

### Issue Authorization Codes with AuthCodeController

An `AuthCodeController` manages the OAuth 2.0 authorization code flow. The authorization code flow is used when an Aqueduct application allows third party applications access to authorized resources.

Let's say you've built an Aqueduct application that allows people to store notes to themselves, and it has users that have created accounts. Now, a friend approaches you with their application that is a to-do list. Instead of building their own note-taking feature, your friend wants their users of their application to access the notes those users have stored in your application. While trustworthy, you don't want your friend to have access to the username and passwords of your subscribers.

To handle this, your friend builds a link into their application that takes the user to a web form hosted by your application. The user enters their credentials in this form and they are sent to your application. Your application responds by redirecting the user's browser back into your friend's application, but with an authorization code in the URL. Your friend's application parses the code from the URL and sends it to their server. Behind the scenes, their server exchanges this code with your server for an access token.

An `AuthCodeController` responds to both `GET` and `POST` requests. When issued a `GET`, it serves up a webpage with a login form. This login form's action sends a `POST` back to the same endpoint with the username and password of the user. Upon success, the response from the `POST` is a 302 redirect with an authorization code.

Setting up an `AuthCodeController` is nearly as simple as setting up an `AuthController`, but requires a function that renders the HTML login form. Here's an example:

```dart
@override
void setupRouter(Router router) {
  router
    .route("/auth/code")
    .generate(() => new AuthCodeController(
      authServer, renderAuthorizationPageHTML: renderLogin));
}

Future<String> renderLogin(
    AuthCodeController requestingController,
    URI requestURI,
    Map<String, String> queryParameters) {
  var html = HTMLRenderer.templateWithSubstitutions(
    "web/login.html", requestURI, queryParameters);

  return html;
}
```

It is important that all values passed to HTML rendering function are sent in the form's query parameters - they contain necessary security components and scope information. (The default project created with `aqueduct create` has an implementation with a simple login form that does this.)

When your friend's application links to your login page - here, a `GET /auth/code` - they must include three query parameters: `state`, `client_id`, `response_type`. They may optionally include `scope`:

```
GET https://stablekernel/auth/code?client_id=friend.app&response_type=code&state=87uijn3rkja
```

The value of `client_id` must be a previously created client identifier specifically made for your friend's application. (See more on generating client identifiers with `aqueduct auth` in [Aqueduct Auth CLI](cli.md).) The `response_type` must always be `code`. The `state` must be a value your friend's application creates.

When your application redirects back to your friend's application, both the generated authorization code and the value for `state` will be query parameters in the URL. It is your friend's job to ensure that the `state` matches the state they provided to the initial `GET`. (They probably generated it from a session cookie.) That redirect URL will look like:

```
https://friends.app/code_callback?code=abcd672kk&state=87uijn3rkja
```

The redirect URL is pre-determined when generating the client identifier with `aqueduct auth`.

Once your friend's application has an authorization code, it is sent to their server. To exchange the code, a `POST` to an `AuthController` - *NOT* the `AuthCodeController` - with the following body will return a token response:

```
grant_type=authorization_code&code=abcd672kk
```
