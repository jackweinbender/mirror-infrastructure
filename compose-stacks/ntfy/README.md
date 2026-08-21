# ntfy

ntfy runs on `docker0-lxc` and is exposed through the host Traefik at
`https://ntfy.weinbender.io`. The hostname is defined in
`deployments/docker0-lxc/.env.template`.

The stack follows the [ntfy Docker installation guidance](https://docs.ntfy.sh/install/),
using the pinned `binwiederhier/ntfy:v2.27.0` image. Cache, attachments, and the
ntfy authentication database are stored in named Docker volumes. On
`docker0-lxc`, those volumes follow the host-backed Docker data root at
`/srv/guest-volumes/docker`.

Topic access defaults to `deny-all`; create ntfy users and grants from the
running container before publishing or subscribing:

```bash
docker exec -it ntfy ntfy user add <username>
docker exec -it ntfy ntfy access <username> <topic> read-write
```

The service uses the external `proxy` network provided by
`docker-networking`. Add an unproxied Cloudflare CNAME for
`ntfy.weinbender.io` pointing to the `docker0-lxc` Traefik gateway hostname as
described in the [Traefik README](../traefik/README.md).
