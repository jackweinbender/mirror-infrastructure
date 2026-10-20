# logging role

Owns Vector installation, journald and Docker log sources, sink configuration,
permissions, and the Vector service lifecycle. The Debian host profile applies
host logging; the stack-host profile adds the Docker source after Docker is
installed. Stack hosts defer Vector startup until both sources are configured.
