# ntfy

The stack definition is present, but no `deployments/` assignment currently
targets a host. The repository does not establish whether an instance is
running remotely. Add `deployments/<host>/.env.template` to assign it to a
deployment host.

The stack follows the [ntfy Docker installation guidance](https://docs.ntfy.sh/install/),
using the pinned `binwiederhier/ntfy:v2.27.0` image. Cache, attachments, and the
ntfy authentication database are stored in named Docker volumes. When assigned
to `docker0-lxc`, those volumes follow the host-backed Docker data root at
`/srv/guest-volumes/docker`.

Topic access defaults to `deny-all`; create ntfy users and grants from the
running container before publishing or subscribing:

```bash
docker exec -it ntfy ntfy user add <username>
docker exec -it ntfy ntfy access <username> <topic> read-write
```

When assigned to `docker0-lxc`, the service uses the external `proxy` network
ensured by c5e; it does not create or manage that network. Add an unproxied
Cloudflare CNAME for `ntfy.weinbender.io` pointing to the `docker0-lxc` Traefik
gateway hostname as described in the [Traefik README](../traefik/README.md).
