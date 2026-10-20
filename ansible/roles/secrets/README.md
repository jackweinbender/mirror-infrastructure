# secrets role

Owns the root-only c5e service-account environment file used by the c5e
application. The targeted c5e playbook supplies the credential privately; normal
stack-host convergence only preserves permissions on an existing file. This is
the first concrete secret consumer, not a general host/LXC secret-distribution
system.
