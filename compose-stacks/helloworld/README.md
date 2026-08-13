# helloworld

A minimal application stack used to practice deployment. It runs one HTTP service on every Docker host with `host_roles: deploy` and returns a static response identifying the host:

```text
hello from <hostname>
```

The service is available through the host Traefik at `http://<host>/hello`. Each assignment file supplies the hostname used in the response, while the application remains otherwise identical across hosts.

Assignments are controlled by `deployments/<host>/.env.template` files; add or remove a deployment directory to change which deploy hosts run the stack. An optional `deployments/<host>/docker-compose.yaml` overlay is copied to the remote stage as `docker-compose.override.yaml`, matching the normal application deployment pattern. The normal `deploy.yaml` workflow reconciles `docker-networking` first, then deploys Traefik and this application stack.
