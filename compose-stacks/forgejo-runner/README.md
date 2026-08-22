# Forgejo Runner

Forgejo Runner runs on `docker0-lxc` as a separate stack from Forgejo. It uses
Forgejo Runner `v13.0.0` with the Docker backend and advertises the `docker`
label required by the repository workflows.

The runner's registration and configuration data are stored in the named Docker
volume `forgejo_runner_data`. The Docker socket is mounted because the runner
creates isolated containers for workflow jobs; this gives workflow code control
of the Docker daemon and should be treated as equivalent to host-level access.
The stack is intentionally not attached to the public `proxy` network and has no
public ingress.

## One-time registration

After the stack has been deployed, create a repository, organization, or user
runner in Forgejo and copy its registration token. Register it from the host
with the runner image, replacing the placeholders with the actual Forgejo URL,
token, and registration scope:

```bash
docker run --rm \
  --mount source=forgejo_runner_data,target=/data \
  code.forgejo.org/forgejo/runner:13.0.0 \
  register \
  --no-interactive \
  --instance https://git.weinbender.io \
  --token '<registration-token>' \
  --name docker0-lxc \
  --labels docker:docker://node:22-bookworm
```

The registration command writes `/data/.runner` in the persistent volume. Do
not put the registration token in Git or in a runtime `.env` file. If the runner
needs to be registered again, stop the stack first and remove only the runner's
configuration from its named volume after confirming the intended registration
scope.

Once registered, start or restart the stack and confirm in the repository's
**Settings → Actions → Runners** page that `docker0-lxc` is online and has the
`docker` label. The default job image can be changed in the runner
configuration if the workflows need tools not present in the default image. The
current workflows require Ruby in addition to Node, Bash, Git, and apt; either
install Ruby in the affected workflow jobs or use a custom image that includes
it.
