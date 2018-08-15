# Deploying an Aqueduct Application using Docker

For other deployment options, see [Deploying Aqueduct Applications](index.md).

### Purpose

This document will describe the steps to deploy an Aqueduct application through Docker and/or a container orchestration platform like Kubernetes. For Dockerfile and Kubernetes templates, see [this repository](https://github.com/stablekernel/kubernetes).

If you are unfamiliar with deploying applications in this way, this is not a good beginner's guide and will not cover the topics of Docker or Kubernetes.

### Dockerfiles

The following Dockerfile will run an Aqueduct application.

```
FROM google/dart

WORKDIR /app
ADD pubspec.* /app/
RUN pub get --no-precompile
ADD . /app/
RUN pub get --offline --no-precompile

WORKDIR /app
EXPOSE 80

ENTRYPOINT ["pub", "run", "aqueduct:aqueduct", "serve", "--port", "80"]
```

### Kubernetes Objects

For more Kubernetes objects - including tasks for database migrations and OAuth 2.0 client management - see [this repository](https://github.com/stablekernel/kubernetes). The following is Kubernetes configuration file for starting an Aqueduct application and exposing it as a service. Replace `<APP_NAME>` with your application's name.

```
apiVersion: v1
kind: Service
metadata:
  name: api-service
  namespace: <APP_NAME>
spec:
  selector:
    app: <APP_NAME>
    role: backend
    type: api
  ports:
    - port: 80
      targetPort: 8082
---
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: api-deployment
  namespace: <APP_NAME>
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: <APP_NAME>
        role: backend
        type: api
    spec:
      containers:
        - name: <APP_NAME>
          # In development, setting `imagePullPolicy: Always` and using :latest tag is useful.
          # imagePullPolicy: Always
          image: <IMAGE>
          envFrom:
            - secretRef:
                name: secrets
            - configMapRef:
                name: config
          ports:
            - containerPort: 8082
      securityContext:
              runAsNonRoot: true
```
