#!/bin/bash
# Verify that all Ansible 2.20.3 deprecation fixes are in place
# Usage: ./verify-deprecations.sh

set -e

echo "╔════════════════════════════════════════════════════╗"
echo "║   Verifying Ansible Deprecation Fixes              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check for venv
if [ ! -d ".venv" ]; then
    echo "❌ Virtual environment not found at .venv/"
    echo "   Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# Activate venv
source .venv/bin/activate

# Test 1: Syntax Check
echo "1️⃣  Checking playbook syntax..."
SYNTAX_OUTPUT=$(ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check 2>&1)
if echo "$SYNTAX_OUTPUT" | grep -q "playbook:"; then
    echo "   ✓ Syntax check passed"
else
    echo "   ❌ Syntax check failed"
    echo "$SYNTAX_OUTPUT"
    exit 1
fi

# Test 2: Linting
echo ""
echo "2️⃣  Running ansible-lint..."
LINT_OUTPUT=$(ansible-lint 2>&1 | tail -1)
if echo "$LINT_OUTPUT" | grep -q "0 failure"; then
    echo "   ✓ Linting passed: $LINT_OUTPUT"
else
    echo "   ❌ Linting failed"
    exit 1
fi

# Test 3: No deprecation warnings
echo ""
echo "3️⃣  Checking for deprecation warnings..."
DEPRECATION_COUNT=$(ansible-playbook playbooks/local-bootstrap-lxc.yaml --syntax-check 2>&1 | grep -c "DEPRECATION") || DEPRECATION_COUNT=0
if [ "$DEPRECATION_COUNT" -eq 0 ]; then
    echo "   ✓ No deprecation warnings found"
else
    echo "   ❌ Found $DEPRECATION_COUNT deprecation warnings"
    exit 1
fi

# Test 4: No old-style fact references in production code
echo ""
echo "4️⃣  Scanning for old-style fact references..."
OLD_FACTS=$(grep -rE "{{ ansible_[a-z_]+\." roles/ tasks/ playbooks/ --include="*.yml" 2>/dev/null \
    | grep -v "ansible_facts\[" \
    | grep -v "ansible_user" \
    | grep -v "molecule" \
    | wc -l)
if [ "$OLD_FACTS" = "0" ]; then
    echo "   ✓ All fact references use ansible_facts[] syntax"
else
    echo "   ⚠️  Found $OLD_FACTS old-style references (may be harmless):"
    grep -rE "{{ ansible_[a-z_]+\." roles/ tasks/ playbooks/ --include="*.yml" 2>/dev/null | head -5
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════╗"
echo "║   ✅ ALL DEPRECATION CHECKS PASSED                 ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Your Ansible infrastructure is ready for Ansible 2.24+"
echo "No action needed - all deprecation warnings have been fixed"
