#!/bin/bash
# Quick reference for molecule testing commands
# Source this or copy the commands to your shell

set -e

echo "Molecule Quick Reference"
echo "======================="
echo ""
echo "Prerequisites:"
echo "  - Docker or Podman running"
echo "  - cd ansible && source .venv/bin/activate"
echo ""
echo "Common commands:"
echo ""
echo "  # Full test (create → apply → verify → destroy)"
echo "  molecule test -s base"
echo ""
echo "  # Apply and inspect"
echo "  molecule converge -s base"
echo "  docker exec -it debian-bookworm bash"
echo "  molecule destroy -s base"
echo ""
echo "  # Test idempotency (run twice, second should have no changes)"
echo "  molecule idempotent -s base"
echo ""
echo "  # List instances"
echo "  molecule list -s base"
echo ""
echo "  # View logs of a failed test"
echo "  molecule converge -s base -vv"
echo ""
echo "See ansible/TESTING.md for detailed documentation."
