# c5e reconciler bootstrap

Assigned to `lxc-docker-core0` via this directory's empty `.env.template`, with
a C5E host ID matching that inventory host. It uses the standard
`forgejo.weinbender.io/labs/c5e:main` image and reconciles stacks assigned to
that host. `--deploy-host=false` skips host configuration, while
`--removal-policy=retain` preserves removed stacks.

The controller reads the public infrastructure repository at `main`; host
`/etc/compose-stacks` is mounted read-only at the same path. State is kept in
named volume `c5e_reconciler_state` at `/var/lib/c5e-state`. Its
`C5E_OP_CREDENTIALS` variable is unset; the core0 Traefik assignment contains
1Password references, so C5E needs valid credentials to reconcile that stack.

Push changes to `main` to trigger `.crow/deploy-c5e-reconciler.yaml` after the
platform deployment. For a manual deployment, run from the repository root:

```sh
ruby scripts/reconcile-host.rb lxc-docker-core0 lxc-docker-core0.tortoise-noodlefish.ts.net c5e-reconciler
```

The container runs as root to avoid an unverified socket GID; this assumes a
root-owned Docker socket. Socket access is host-root-equivalent. The root
filesystem is read-only, capabilities are dropped, `no-new-privileges` is set,
and only the state volume and `/tmp` are writable. The controller is not a
security sandbox.
