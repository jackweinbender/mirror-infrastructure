# c5e reconciler bootstrap

Assigned to `lxc-docker-core0` via its `.env.template`, which sets
`C5E_HOSTNAME=c5e-core0.weinbender.io`. It uses the standard
`forgejo.weinbender.io/labs/c5e:main` image and reconciles stacks assigned to
that host. `--deploy-host=false` skips host configuration, while
`--removal-policy=retain` preserves removed stacks.

The dashboard listens on container port `8080` and is routed through host-level
Traefik at `https://c5e-core0.weinbender.io/`. The service joins the external
`proxy` network to make it available to Traefik.

The controller reads the public infrastructure repository at `main`; host
`/var/lib/c5e-live` is mounted at the same path. State is kept in named volume
`c5e_reconciler_state` at `/var/lib/c5e-state`. `C5E_OP_CREDENTIALS` uses the
core0 assignment's 1Password reference so C5E can reconcile stacks containing
secret references.

Push changes to `main` to trigger `.crow/deploy-c5e-reconciler.yaml` after the
platform deployment. For a manual deployment, run from the repository root:

```sh
ruby scripts/reconcile-host.rb lxc-docker-core0 lxc-docker-core0.tortoise-noodlefish.ts.net c5e-reconciler
```

The container runs as root and mounts the host's Docker socket, which grants
host-root-equivalent access. Traefik terminates HTTPS for the dashboard route;
no authentication middleware is configured for this route.
