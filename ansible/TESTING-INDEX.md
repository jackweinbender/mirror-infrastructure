# Ansible Testing Documentation Index

Complete reference for testing your Ansible infrastructure roles and tasks.

## Quick Navigation

### For First-Time Users
1. **Start here:** `README.md` → "Testing with Molecule" section
2. **Full guide:** `TESTING.md` (comprehensive, all workflows)
3. **Try it:** `molecule test -s base` (with Docker running)

### For Role Development
- **Base role:** `roles/base/molecule/README.md`
- **Docker role:** `roles/docker/molecule/README.md`
- **Tailscale role:** `roles/tailscale/molecule/README.md`
- **Custom roles:** See "Adding Tests for Custom Roles" in `TESTING.md`

### For Infrastructure as Code
- **Bootstrap tasks:** `TESTING-TASKS.md`
- **Syntax checking:** See `TESTING-TASKS.md` → "Syntax Validation"
- **Dry-runs:** See `TESTING-TASKS.md` → "Dry-Run on Real Infrastructure"

### For CI/CD Integration
- **GitHub Actions:** See `TESTING.md` → "CI/CD Integration"
- **Workflow examples:** `TESTING.md` → "CI/CD Integration" section

---

## Documentation Files

### Core Testing Guides

| File | Purpose | Length | Audience |
|------|---------|--------|----------|
| `TESTING.md` | Complete testing guide with all workflows | 7000 words | Everyone |
| `TESTING-TASKS.md` | Bootstrap/procedural task testing | 4000 words | Infrastructure editors |
| `TESTING-INDEX.md` | This file—navigation guide | — | Everyone |

### Role-Specific Documentation

| File | Coverage | Assertions | Audience |
|------|----------|-----------|----------|
| `roles/base/molecule/README.md` | Base role (users, packages, locale) | 6 checks | Role developers |
| `roles/docker/molecule/README.md` | Docker Engine + Compose + groups | 8 checks | Docker users |
| `roles/tailscale/molecule/README.md` | Tailscale installation + daemon | 10 checks | Tailscale users |

### Main Documentation

| File | Section | Relevant To |
|------|---------|-------------|
| `README.md` | "Testing with Molecule" | Quick start |
| `AGENTS.md` | (No changes) | Role structure |

---

## Test Suites

### Base Role (`roles/base/molecule/`)
```
roles/base/molecule/
├── README.md              ← Why and how to test base role
├── default/
│   ├── molecule.yml       ← Container config (Debian bookworm)
│   ├── converge.yml       ← Apply base role
│   └── verify.yml         ← Validate: users, packages, locale, tz, ssh, shells
```

**Test:** `molecule test -s base`

**Verifies:**
- ansible user exists
- Required packages (openssh-server, sudo, curl, git, vim)
- Locale set to en_US.UTF-8
- Timezone symlink at /etc/localtime
- SSH service running
- Shell assignments (ansible→bash, root→zsh)

### Docker Role (`roles/docker/molecule/`)
```
roles/docker/molecule/
├── README.md              ← Why and how to test docker role
├── default/
│   ├── molecule.yml       ← Container config
│   ├── converge.yml       ← Apply base role + docker role
│   └── verify.yml         ← Validate: docker, compose, groups, permissions
```

**Test:** `molecule test -s docker`

**Verifies:**
- Docker Engine installed and running
- Docker Compose plugin installed
- docker group exists
- ansible user in docker group
- jlw user (from base_extra_sudo_users) in docker group
- Passwordless docker access for both users
- Official Docker repository configured
- Docker daemon enabled and running

### Tailscale Role (`roles/tailscale/molecule/`)
```
roles/tailscale/molecule/
├── README.md              ← Why and how to test tailscale role
├── default/
│   ├── molecule.yml       ← Container config
│   ├── converge.yml       ← Apply base role + tailscale role
│   └── verify.yml         ← Validate: installation, daemon, repo, gpg
```

**Test:** `molecule test -s tailscale`

**Verifies:**
- tailscale binary installed and executable
- tailscaled daemon installed
- Tailscale official repository configured
- Tailscale GPG key installed and valid
- tailscaled service running and enabled
- tailscale command working (version, help)
- Package installed via apt

---

## How to Use Tests

### Run All Role Tests
```bash
cd ansible
source .venv/bin/activate
molecule test -s base       # Base role
molecule test -s docker     # Docker role (depends on base)
molecule test -s tailscale  # Tailscale role (depends on base)
```

### Interactive Development
```bash
molecule converge -s docker
docker exec -it debian-bookworm bash
  # Inspect: docker ps, sudo -l, etc.
molecule destroy -s docker
```

### Test Idempotency
```bash
molecule idempotent -s docker
```

### Debug a Failure
```bash
molecule converge -s docker -vv  # Verbose output
docker logs debian-bookworm      # Container logs
docker exec -it debian-bookworm bash  # Interactive inspection
```

---

## What Gets Tested Where

### Roles (Molecule Tests)
✅ `base` role — Debian baseline configuration  
✅ `docker` role — Docker Engine + Compose  
✅ `tailscale` role — Tailscale VPN client  

### Tasks (No Unit Tests, Use Alternatives)
⚠️ `tasks/lxc_bootstrap/` — Use syntax check + dry-run (see TESTING-TASKS.md)  
⚠️ `tasks/lxc_prepare/` — Use syntax check + dry-run  
⚠️ `tasks/lxc_create/` — Use syntax check + dry-run  
⚠️ `tasks/lxc_features/` — Use syntax check + dry-run  
⚠️ `tasks/pve_host/` — Use syntax check + dry-run  

**Reason:** Tasks require Proxmox infrastructure and make irreversible changes. Test via syntax check + dry-run instead (see `TESTING-TASKS.md`).

### All YAML
✅ `ansible-lint` — Syntax, style, common mistakes (CI automated)  
✅ `ansible-playbook --syntax-check` — YAML structure (CI automated)  

---

## Testing Pyramid

```
        ┌─────────────────────────┐
        │  Production Integration │
        │  (CI on real hosts)      │
        └────────────┬────────────┘
                     △
        ┌────────────┴────────────┐
        │  Dry-Run Validation     │
        │  (Manual before commit) │
        └────────────┬────────────┘
                     △
        ┌────────────┴────────────┐
        │  Role Testing (Molecule)│
        │  (Local with Docker)    │
        └────────────┬────────────┘
                     △
        ┌────────────┴────────────┐
        │  Linting + Syntax Check │
        │  (Free, automated)      │
        └─────────────────────────┘
```

**Flow:**
1. **Lint + Syntax** (catches basic errors)
2. **Molecule Tests** (validates roles work in isolation)
3. **Dry-Run** (preview real infrastructure impact)
4. **Integration** (actual deployment to production)

---

## Common Commands

### Test a Single Role
```bash
molecule test -s base       # Test base role
molecule test -s docker     # Test docker role
molecule test -s tailscale  # Test tailscale role
```

### Develop Interactively
```bash
molecule converge -s docker     # Apply and keep running
docker exec -it debian-bookworm bash  # Inspect
molecule destroy -s docker      # Clean up
```

### Test Idempotency
```bash
molecule idempotent -s docker   # Apply twice, second should change nothing
```

### Lint and Syntax Check
```bash
ansible-lint                     # Lint all YAML
ansible-playbook playbooks/workloads.yaml --syntax-check
```

### Dry-Run on Real Infrastructure (Before Applying)
```bash
ansible-playbook playbooks/workloads.yaml --check --diff
```

---

## File Structure

```
ansible/
├── README.md                    # Includes quick start for Molecule
├── TESTING.md                   # Complete testing guide
├── TESTING-TASKS.md             # Bootstrap task testing guide
├── TESTING-INDEX.md             # This file
├── .molecule-quickstart.sh      # Quick command reference
├── ansible.cfg                  # Ansible configuration
├── requirements.txt             # Dependencies (includes molecule)
├── inventory.yaml               # Host inventory
├── roles/
│   ├── base/
│   │   ├── tasks/
│   │   │   └── *.yml
│   │   ├── defaults/main.yml
│   │   └── molecule/            # ← Test suite
│   │       ├── README.md
│   │       └── default/
│   │           ├── molecule.yml
│   │           ├── converge.yml
│   │           └── verify.yml
│   ├── docker/
│   │   ├── tasks/
│   │   ├── defaults/main.yml
│   │   └── molecule/            # ← Test suite
│   │       ├── README.md
│   │       └── default/
│   │           ├── molecule.yml
│   │           ├── converge.yml
│   │           └── verify.yml
│   └── tailscale/
│       ├── tasks/
│       ├── defaults/main.yml
│       └── molecule/            # ← Test suite
│           ├── README.md
│           └── default/
│               ├── molecule.yml
│               ├── converge.yml
│               └── verify.yml
├── tasks/
│   ├── lxc_bootstrap/
│   ├── lxc_prepare/
│   ├── lxc_create/
│   ├── lxc_features/
│   └── pve_host/
└── playbooks/
    ├── workloads.yaml
    ├── local-bootstrap-lxc.yaml
    └── ...
```

---

## Troubleshooting

### "Docker daemon is not running"
Start Docker Desktop or use Podman.

### "Container exits unexpectedly"
Check logs: `docker logs debian-bookworm`

### "Module not found during verify"
Reinstall requirements: `pip install -r ansible/requirements.txt`

### "Idempotency test fails"
Your role changed something on the second run. This is a bug in the role. See `TESTING.md` → "Common Issues" → "Idempotency test fails" for solutions.

### "Group membership checks fail" (docker role)
Ensure base role ran first. The test playbook should apply both automatically.

### "Tailscale daemon not running"
Normal—it may take a moment. Check: `docker exec -it debian-bookworm systemctl status tailscaled`

For more troubleshooting, see the specific role's README or `TESTING.md`.

---

## Next Steps

1. **First time?** Read `README.md` → "Testing with Molecule"
2. **Try it:** `molecule test -s base` (Docker must be running)
3. **Explore:** `molecule converge -s docker` + `docker exec -it debian-bookworm bash`
4. **Learn:** Read `TESTING.md` for complete guide
5. **Deploy:** Bootstrap test container, verify with roles, then production

---

## Key Resources

- **[Molecule Documentation](https://molecule.readthedocs.io/)** — Official reference
- **[Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)** — Ansible standards
- **`TESTING.md`** — Your complete testing guide
- **`TESTING-TASKS.md`** — Bootstrap task testing strategy

---

## Questions?

- **Role-specific:** See `roles/{role}/molecule/README.md`
- **General testing:** See `TESTING.md`
- **Bootstrap/tasks:** See `TESTING-TASKS.md`
- **Quick start:** See `README.md` section "Testing with Molecule"
