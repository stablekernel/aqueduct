# Documenting Aqueduct Applications

The `aqueduct document` tool generates an OpenAPI (formerly Swagger) specification by reflecting on your application's code. This command is run in a project directory and will emit the JSON specification to stdout. You can redirect this to a file:

```
aqueduct document > swagger.json
```

The file `config.src.yaml` must exist in your project directory so that the application can be initialized in 'test' mode for the documentation to be generated.
