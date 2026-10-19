# c5e reconciler bootstrap

Assigned only to `lxc-docker-core0` by this directory's empty `.env.template`.
The controller uses the standard `forgejo.weinbender.io/labs/c5e:main` image,
but its synthetic host ID (`lxc-docker-core0-canary`) matches no workload
assignments. `--deploy-host=false` and `--removal-policy=retain` keep it from
managing app or platform stacks.

The controller reads the public infrastructure repository at `main`; host
`/etc/compose-stacks` is mounted read-only at the same path. State is kept in
named volume `c5e_reconciler_state` at `/var/lib/c5e-state`. No app secrets or
1Password credential values are configured. c5e requires a credential
environment-variable name, which is set but unset; future `op://` inputs need
credentials configured deliberately.

Deploy manually from the repository root:

```sh
ruby scripts/reconcile-host.rb lxc-docker-core0 lxc-docker-core0.tortoise-noodlefish.ts.net c5e-reconciler
```

The container runs as root to avoid an unverified socket GID; this assumes a
root-owned Docker socket. Socket access is host-root-equivalent. The root
filesystem is read-only, capabilities are dropped, `no-new-privileges` is set,
and only the state volume and `/tmp` are writable. This trusted-source canary is
not a sandbox; enabling workload management needs a separate review.
