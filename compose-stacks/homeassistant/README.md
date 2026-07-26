# compose-stacks/homeassistant

Home Assistant + MQTT broker + Zigbee2MQTT stack. Runs on a self-hosted VM (Proxmox) via `network_mode: host`.

## Services

| Service | Image | Port | Notes |
|---------|-------|------|-------|
| `homeassistant` | `ghcr.io/home-assistant/home-assistant:stable` | 8123 (host) | Config in `./homeassistant` |
| `mosquitto` | `eclipse-mosquitto:2` | 1883/9001 (host) | Config in `./mosquitto`, data in volumes |
| `zigbee2mqtt` | `koenkk/zigbee2mqtt:latest` | 8080 (host) | Requires Zigbee dongle at `/dev/serial/by-id/...` |

## Zigbee Dongle

Update `docker-compose.yaml` device mapping:

```yaml
devices:
  - /dev/serial/by-id/<YOUR_DONGLE_ID>:/dev/ttyUSB0
```

Find ID: `ls /dev/serial/by-id/` on the VM.

## Config

- `./homeassistant/` — HA config (configuration.yaml, automations, etc.)
- `./mosquitto/` — mosquitto.conf
- `./zigbee2mqtt/` — configuration.yaml

## Secrets (.env.template)

```bash
# No secrets required for base stack
# Add any HA-specific secrets (API keys, etc.) as needed
```

## Deploy

```bash
# Local
cp .env.template .env
docker compose up -d

# CI/CD
# GitHub Actions workflow_dispatch → deploy.yaml → selects 'homeassistant' stack
```

## Validate HA Config

```bash
docker run --rm -v $(pwd)/homeassistant:/config ghcr.io/home-assistant/home-assistant:stable hass --script check_config --config /config
```

Runs automatically in deploy workflow.

## Network

`network_mode: host` required for:
- Home Assistant device discovery (mDNS, UPnP)
- Zigbee2MQTT serial access
- MQTT local clients