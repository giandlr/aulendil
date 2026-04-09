#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────
# Refresh Dependencies — Query latest stable versions
#
# Usage: bash scripts/refresh-deps.sh
#
# Queries PyPI and npm for the latest stable versions of
# all project dependencies and updates requirements.txt,
# requirements-dev.txt, and package.json with exact pins.
#
# Offline fallback: if APIs are unreachable, keeps current
# versions unchanged.
# ─────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Dependency Refresh"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════"
echo ""

CHANGES=()

# ── Helpers ──────────────────────────────────────────

get_latest_pypi_version() {
    local pkg="$1"
    local fallback="$2"
    local v
    v=$(curl -sf --max-time 5 "https://pypi.org/pypi/${pkg}/json" \
      | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
    if [ -n "$v" ]; then
        echo "$v"
    else
        echo "$fallback"
    fi
}

get_latest_npm_version() {
    local pkg="$1"
    local fallback="$2"
    local v
    v=$(curl -sf --max-time 5 "https://registry.npmjs.org/${pkg}/latest" \
      | grep -o '"version":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
    if [ -n "$v" ]; then
        echo "$v"
    else
        echo "$fallback"
    fi
}

# ── Python Backend ───────────────────────────────────

if [ -f "backend/requirements.txt" ]; then
    echo "Checking Python dependencies..."
    echo ""

    TMPFILE=$(mktemp)

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and blank lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// /}" ]]; then
            echo "$line" >> "$TMPFILE"
            continue
        fi

        # Extract package name (handle ==, >=, ~=, etc.)
        pkg_name=$(echo "$line" | sed -E 's/^([a-zA-Z0-9_-]+(\[[a-zA-Z0-9_,-]+\])?).*/\1/')
        pkg_base=$(echo "$pkg_name" | sed -E 's/\[.*\]//')
        old_version=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1)

        if [ -z "$old_version" ]; then
            echo "$line" >> "$TMPFILE"
            continue
        fi

        new_version=$(get_latest_pypi_version "$pkg_base" "$old_version")
        echo "${pkg_name}==${new_version}" >> "$TMPFILE"

        if [ "$old_version" != "$new_version" ]; then
            echo "  ${pkg_base}: ${old_version} → ${new_version}"
            CHANGES+=("${pkg_base}: ${old_version} → ${new_version}")
        else
            echo "  ${pkg_base}: ${old_version} (current)"
        fi
    done < "backend/requirements.txt"

    mv "$TMPFILE" "backend/requirements.txt"
    echo ""
fi

if [ -f "backend/requirements-dev.txt" ]; then
    echo "Checking Python dev dependencies..."
    echo ""

    TMPFILE=$(mktemp)

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// /}" ]]; then
            echo "$line" >> "$TMPFILE"
            continue
        fi

        pkg_name=$(echo "$line" | sed -E 's/^([a-zA-Z0-9_-]+(\[[a-zA-Z0-9_,-]+\])?).*/\1/')
        pkg_base=$(echo "$pkg_name" | sed -E 's/\[.*\]//')
        old_version=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+[.0-9]*' | head -1)

        if [ -z "$old_version" ]; then
            echo "$line" >> "$TMPFILE"
            continue
        fi

        new_version=$(get_latest_pypi_version "$pkg_base" "$old_version")
        echo "${pkg_name}==${new_version}" >> "$TMPFILE"

        if [ "$old_version" != "$new_version" ]; then
            echo "  ${pkg_base}: ${old_version} → ${new_version}"
            CHANGES+=("${pkg_base}: ${old_version} → ${new_version}")
        else
            echo "  ${pkg_base}: ${old_version} (current)"
        fi
    done < "backend/requirements-dev.txt"

    mv "$TMPFILE" "backend/requirements-dev.txt"
    echo ""
fi

# ── Frontend (npm) ───────────────────────────────────

if [ -f "frontend/package.json" ] && command -v node &>/dev/null; then
    echo "Checking frontend dependencies..."
    echo ""

    # Update dependencies and devDependencies in package.json
    node -e "
const fs = require('fs');
const { execSync } = require('child_process');
const pkg = JSON.parse(fs.readFileSync('frontend/package.json', 'utf8'));
const changes = [];

function getLatestNpm(name, current) {
    try {
        const result = execSync(
            'curl -sf --max-time 5 https://registry.npmjs.org/' + encodeURIComponent(name) + '/latest',
            { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
        );
        const data = JSON.parse(result);
        if (data.version) return data.version;
    } catch (e) {}
    // fallback: strip ^ ~ >= from current
    return current.replace(/^[\^~>=]+/, '');
}

function updateDeps(deps, label) {
    if (!deps) return;
    for (const [name, current] of Object.entries(deps)) {
        const cleanCurrent = current.replace(/^[\^~>=]+/, '');
        const latest = getLatestNpm(name, current);
        if (latest !== cleanCurrent) {
            console.log('  ' + name + ': ' + cleanCurrent + ' → ' + latest);
            changes.push(name + ': ' + cleanCurrent + ' → ' + latest);
        } else {
            console.log('  ' + name + ': ' + cleanCurrent + ' (current)');
        }
        deps[name] = latest;
    }
}

updateDeps(pkg.dependencies, 'dependencies');
console.log('');
updateDeps(pkg.devDependencies, 'devDependencies');

fs.writeFileSync('frontend/package.json', JSON.stringify(pkg, null, 2) + '\n');

if (changes.length > 0) {
    fs.writeFileSync('/tmp/npm-changes.txt', changes.join('\n'));
}
"
    echo ""

    # Re-install with updated versions
    echo "  Running npm install..."
    cd frontend && npm install 2>&1 | tail -3
    cd ..
    echo ""
fi

# ── Summary ──────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
if [ ${#CHANGES[@]} -gt 0 ]; then
    echo " Updated ${#CHANGES[@]} package(s)"
    echo ""
    for c in "${CHANGES[@]}"; do
        echo "  $c"
    done
else
    echo " All dependencies are already at latest stable versions"
fi
echo "═══════════════════════════════════════════════════════════"
echo ""

# Re-install Python deps if changed
if [ ${#CHANGES[@]} -gt 0 ] && [ -f "backend/requirements.txt" ]; then
    if [ -f "backend/.venv/bin/activate" ]; then
        echo "  Re-installing Python dependencies..."
        source backend/.venv/bin/activate
        pip install -r backend/requirements.txt -r backend/requirements-dev.txt --quiet 2>&1 | tail -3
        deactivate
        echo "  Done."
    elif [ -f "backend/.venv/Scripts/activate" ]; then
        echo "  Re-installing Python dependencies..."
        source backend/.venv/Scripts/activate
        pip install -r backend/requirements.txt -r backend/requirements-dev.txt --quiet 2>&1 | tail -3
        deactivate
        echo "  Done."
    fi
fi

echo ""
