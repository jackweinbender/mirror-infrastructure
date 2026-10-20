# containers role

Installs Docker Engine and the Compose plugin, verifies required Docker host
capabilities, applies explicitly enabled Docker data-root settings, and grants
the configured host-operations users Docker access.

Docker log collection is composed separately through the `logging` role so its
configuration and Vector service lifecycle remain owned by one capability.
