import 'auth.dart';

/// Represents an OAuth 2.0 client ID and secret pair.
class AuthClient {
  /// Creates an instance of [AuthClient].
  AuthClient(this.id, this.hashedSecret, this.salt);

  /// Creates an instance of a public [AuthClient].
  AuthClient.public(this.id);

  /// Creates an instance of [AuthClient] that uses the authorization code grant flow.
  AuthClient.withRedirectURI(
      this.id, this.hashedSecret, this.salt, this.redirectURI);

  /// The ID of the client.
  String id;

  /// The hashed secret of the client.
  ///
  /// This value may be null if the client is public. See [isPublic].
  String hashedSecret;

  /// The salt [hashedSecret] was hashed with.
  ///
  /// This value may be null if the client is public. See [isPublic].
  String salt;

  /// The redirection URI for authorization codes and/or tokens.
  ///
  /// This value may be null if the client doesn't support the authorization code flow.
  String redirectURI;

  /// Whether or not this is a public or confidential client.
  ///
  /// Public clients do not have a client secret and are used for clients that can't store
  /// their secret confidentially, i.e. JavaScript browser applications.
  bool get isPublic => hashedSecret == null;

  /// Whether or not this is a public or confidential client.
  ///
  /// Confidential clients have a client secret that must be used when authenticating with
  /// a client-authenticated request. Confidential clients are used when you can
  /// be sure that the client secret cannot be viewed by anyone outside of the developer.
  bool get isConfidential => hashedSecret != null;

  String toString() {
    return "AuthClient (${isPublic ? "public" : "confidental"}): $id $redirectURI";
  }
}

/// Represents an OAuth 2.0 token.
///
/// [AuthStorage] and [AuthServer] will exchange OAuth 2.0
/// tokens through instances of this type.
class AuthToken {
  /// The value to be passed as a Bearer Authorization header.
  String accessToken;

  /// The value to be passed for refreshing a token.
  String refreshToken;

  /// The time this token was issued on.
  DateTime issueDate;

  /// The time when this token expires.
  DateTime expirationDate;

  /// The type of token, currently only 'bearer' is valid.
  String type;

  /// The identifier of the resource owner.
  ///
  /// Tokens are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The client ID this token was issued from.
  String clientID;

  /// Whether or not this token is expired by evaluated [expirationDate].
  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  /// Emits this instance as a [Map] according to the OAuth 2.0 specification.
  Map<String, dynamic> asMap() {
    var map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in":
          expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    return map;
  }
}

/// Represents an OAuth 2.0 authorization code.
///
/// [AuthStorage] and [AuthServer] will exchange OAuth 2.0
/// authorization codes through instances of this type.
class AuthCode {
  /// The actual one-time code used to exchange for tokens.
  String code;

  /// The client ID the authorization code was issued under.
  String clientID;

  /// The identifier of the resource owner.
  ///
  /// Authorization codes are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The timestamp this authorization code was issued on.
  DateTime issueDate;

  /// When this authorization code expires, recommended for 10 minutes after issue date.
  DateTime expirationDate;

  /// Whether or not this authorization code has already been exchanged for a token.
  bool hasBeenExchanged;

  /// Whether or not this code has expired yet, according to its [expirationDate].
  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }
}

/// Information about an authorized request.
///
/// After a request has passed through an [Authorizer], an instance of this type
/// is created and attached to the request. Instances of this type contain the information
/// that the [Authorizer] obtained from an [AuthValidator] (typically an [AuthServer])
/// about the validity of the credentials in a request.
class Authorization {
  /// Creates an instance of a [Authorization].
  Authorization(this.clientID, this.resourceOwnerIdentifier, this.validator,
      {this.credentials});

  /// The client ID the permission was granted under.
  final String clientID;

  /// The identifier for the owner of the resource, if provided.
  ///
  /// If this instance refers to the authorization of a resource owner, this value will
  /// be its identifying value. For example, in an application where a 'User' is stored in a database,
  /// this value would be the primary key of that user.
  ///
  /// If this authorization does not refer to a specific resource owner, this value will be null.
  final dynamic resourceOwnerIdentifier;

  /// The [AuthValidator] that granted this permission.
  final AuthValidator validator;

  /// Basic authorization credentials, if provided.
  ///
  /// If this instance represents the authorization header of a request with basic authorization credentials,
  /// the parsed credentials will be available in this property. Otherwise, this value is null.
  final AuthBasicCredentials credentials;
}

class AuthScope {
  AuthScope(String scopeString) {
    _segments = _parse(scopeString);
    _lastModifier = _segments.last.modifier;
  }

  List<_AuthScopeSegment> _segments;
  String _lastModifier;

  List<_AuthScopeSegment> _parse(String scopeString) {
    if (scopeString == null || scopeString == "") {
      throw new FormatException(
          "Invalid AuthScope. May not be null or empty string.", scopeString);
    }

    var elements = scopeString
        .split(":")
        .map((seg) => new _AuthScopeSegment(seg))
        .toList();

    var scannedOffset = 0;
    for (var i = 0; i < elements.length - 1; i++) {
      if (elements[i].modifier != null) {
        throw new FormatException(
            "Invalid AuthScope. May only contain modifiers on the last segment.",
            scopeString,
            scannedOffset);
      }

      if (elements[i].name == "") {
        throw new FormatException(
            "Invalid AuthScope. May not contain empty segments or, leading or trailing colons.",
            scopeString,
            scannedOffset);
      }

      scannedOffset += elements[i].toString().length + 1;
    }

    if (elements.last.name == "") {
      throw new FormatException(
          "Invalid AuthScope. May not contain empty segments.",
          scopeString,
          scannedOffset);
    }

    return elements;
  }

  bool allowsScope(AuthScope incomingScope) {
    if (incomingScope._lastModifier != null) {
      // If the modifier of the incoming scope is restrictive,
      // and this scope requires no restrictions, then it's not allowed.
      if (_lastModifier == null) {
        return false;
      }

      // If the incoming scope's modifier doesn't match this one,
      // then we also don't have access.
      if (_lastModifier != incomingScope._lastModifier) {
        return false;
      }
    }

    // If we aren't restricted by modifier, let's make sure we have access.
    var thisIterator = _segments.iterator;
    for (var incomingSegment in incomingScope._segments) {
      thisIterator.moveNext();
      var current = thisIterator.current;

      // If the incoming scope is more restrictive than this scope,
      // then it's not allowed.
      if (current == null) {
        return false;
      }

      // If we have a mismatch here, then we're going
      // down the wrong path.
      if (incomingSegment.name != current.name) {
        return false;
      }
    }

    return true;
  }

  bool allows(String scopeString) {
    return allowsScope(new AuthScope(scopeString));
  }

  bool isExactlyScope(AuthScope scope) {
    var incomingIterator = scope._segments.iterator;
    for (var segment in _segments) {
      incomingIterator.moveNext();
      var incomingSegment = incomingIterator.current;
      if (incomingSegment == null) {
        return false;
      }

      if (incomingSegment.name != segment.name ||
          incomingSegment.modifier != segment.modifier) {
        return false;
      }
    }

    return true;
  }

  bool isExactly(String scopeString) {
    return isExactlyScope(new AuthScope(scopeString));
  }
}

class _AuthScopeSegment {
  _AuthScopeSegment(String segment) {
    var split = segment.split(".");
    if (split.length == 2) {
      name = split.first;
      modifier = split.last;
    } else {
      name = segment;
    }
  }

  String name;
  String modifier;

  String toString() {
    if (modifier == null) {
      return name;
    }
    return "$name.$modifier";
  }
}
