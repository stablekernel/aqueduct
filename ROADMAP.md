# 1.x

### OAuth 2.0/Authorization Improvements
  - Purpose: To give Aqueduct applications behavior closer to the OAuth 2.0 specification, which minimizes usability friction.
  - Notes:
    - Add scopes to tokens, add scopes to authorizers
    - Use redirectURI to report errors during authentication for authorization code flow
    - Abstract Authorizer.authServer into interface that has methods like `authorizationForCredentials` so that AuthServer can be decoupled. Implement this interface for AuthServer.
    - Add default HTML page for auth code login flow, in response to the initial GET /authorize.
    - Add protections for POST /auth/code to ensure the request is coming from the HTML authentication page.
    - Make interface more convenient for setting up authorizers.

### Websocket Support
  - Purpose: Websockets are a common way of implementing bidirectional communication and realtime "push" behavior in an web application and Aqueduct applications should allow for this behavior to be incorporated into the application structure.
  - Notes:
    - RequestController subclass that upgrades requests and then manages events.
      - Must be addressable from inside the application once established, so that events in the application can push data to its connected client. Addressing is application-specific.
      - Must handle errors, cleanup and maintaining connectivity.
      - Must handle working in a RequestController listener stream, i.e. can be behind middleware like Authorizers.
      - Could potentially be sent to another isolate (if detachSocket + sending DetachedSocket across an isolate works), so that one (or more) dedicated isolates handle websocket connections. Looking for a more Erlang architecture here. Another approach would be to set up a separate

### Scripting/Tool Feedback Improvements
  - Purpose: To give better feedback to Aqueduct users executing Aqueduct applications.
  - Notes:
    - Start/stop script needs usage instructions, more information upon start (like port number and success information) and needs a --console/--detached mode. Console mode will run a blocking process in the shell and the log should spit out to the shell, whereas detached uses current behavior.
    - Improve README and provisioning (especially around inserting client ID/client secret) for initial applications.
    - Provide better interface for all aqueduct scripts.
    - Add OpenAPI document generation script to aqueduct tool, not as a standalone.
    - Add client id/secret generation to aqueduct script.

### Database Migration Generation
  - Purpose: To alleviate burden of database migration and reduce error.
  - Notes:
    - For migrations past the initial, create a migration file that has operations already implemented. (This behavior is effectively already available because `Schema` objects can already do a 'diff' via their compare method.)    

### Documentation
  - Purpose: To help developers understand how to use Aqueduct.
  - Notes:
    - See https://github.com/stablekernel/aqueduct/issues/114

### Discussion Forums
  - Purpose: To have a place where developers get can specific questions answered and clear up some of the cruft in Github issues.

### Examples of Aqueduct Applications
  - Purpose: To help newcomers get acquainted with Aqueduct and start from a better foundation for common web application features.
  - Notes:
    - A message board application
    - A social network application

# 2.0

### Support Sharing Managed Objects across client/server

### Support Other Databases
