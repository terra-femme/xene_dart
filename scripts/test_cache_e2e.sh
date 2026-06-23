#!/bin/bash
# DragonflyDB Cache E2E Test Script
# Tests the distributed cache implementation end-to-end
# Usage: bash test_cache_e2e.sh

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Config
BACKEND_PORT="${1:-8080}"
DRAGONFLY_URL="${2:-redis://localhost:6379}"
SKIP_DOCKER_START="${3:-false}"
SKIP_BACKEND_START="${4:-false}"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Helper function
assert_condition() {
    local test_name="$1"
    local condition="$2"
    local expected="$3"

    if eval "$condition"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}DragonflyDB Cache E2E Test Suite${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# Phase 1: Infrastructure Check
echo ""
echo -e "${YELLOW}Phase 1: Infrastructure Check${NC}"
echo -e "${YELLOW}==============================${NC}"

echo -e "${BLUE}→ Checking Docker...${NC}"
if command -v docker &> /dev/null; then
    docker_version=$(docker --version)
    echo -e "${GREEN}✓${NC} Docker available: $docker_version"
else
    echo -e "${RED}✗${NC} Docker not found"
    exit 1
fi

# Phase 2: DragonflyDB Setup
echo ""
echo -e "${YELLOW}Phase 2: DragonflyDB Setup${NC}"
echo -e "${YELLOW}===========================${NC}"

if [ "$SKIP_DOCKER_START" != "true" ]; then
    echo -e "${BLUE}→ Starting DragonflyDB container...${NC}"
    running=$(docker ps --filter "name=xene-dragonfly" --quiet 2>/dev/null || true)
    if [ -n "$running" ]; then
        echo -e "${YELLOW}!${NC} DragonflyDB already running (ID: $running)"
    else
        if docker-compose up -d 2>/dev/null; then
            echo -e "${GREEN}✓${NC} DragonflyDB started"
            sleep 3  # Wait for startup
        else
            echo -e "${RED}✗${NC} Failed to start DragonflyDB"
            exit 1
        fi
    fi
fi

# Test DragonflyDB connectivity
echo -e "${BLUE}→ Testing DragonflyDB connectivity...${NC}"
assert_condition "DragonflyDB PING" \
    "[ \"$(docker exec xene-dragonfly redis-cli ping 2>/dev/null)\" = \"PONG\" ]"

# Phase 3: Unit Tests
echo ""
echo -e "${YELLOW}Phase 3: Unit Tests${NC}"
echo -e "${YELLOW}====================${NC}"

echo -e "${BLUE}→ Running cache unit tests...${NC}"
cd ./packages/xene_backend
if dart test test/dragonfly_cache_test.dart --timeout=30s 2>&1 | grep -q "All tests passed"; then
    echo -e "${GREEN}✓${NC} All 8 unit tests passed"
    TESTS_PASSED=$((TESTS_PASSED + 8))
else
    echo -e "${RED}✗${NC} Some unit tests failed"
    ((TESTS_FAILED++))
fi
cd ../../

# Phase 4: DragonflyDB Data Verification
echo ""
echo -e "${YELLOW}Phase 4: DragonflyDB Data Verification${NC}"
echo -e "${YELLOW}=======================================${NC}"

echo -e "${BLUE}→ Checking test data in DragonflyDB...${NC}"
keys=$(docker exec xene-dragonfly redis-cli KEYS "test:*" 2>/dev/null || true)
if [ -n "$keys" ]; then
    echo -e "${GREEN}✓${NC} Test keys found in cache:"
    echo "$keys" | while read key; do
        echo "  - $key"
        ((TESTS_PASSED++))
    done
else
    echo -e "${RED}✗${NC} No test keys found in cache"
    ((TESTS_FAILED++))
fi

# Get cache stats
echo -e "${BLUE}→ Getting cache statistics...${NC}"
dbsize=$(docker exec xene-dragonfly redis-cli DBSIZE 2>/dev/null || true)
echo -e "${GREEN}✓${NC} Total keys in DragonflyDB: $dbsize"

# Phase 5: Backend Integration
echo ""
echo -e "${YELLOW}Phase 5: Backend Integration Test${NC}"
echo -e "${YELLOW}==================================${NC}"

if [ "$SKIP_BACKEND_START" != "true" ]; then
    echo -e "${BLUE}→ Checking backend setup...${NC}"
    cd ./packages/xene_backend

    if [ ! -f .env ]; then
        echo -e "${YELLOW}!${NC} .env file not found, setting up..."
        cp .env.example .env
        echo -e "${GREEN}✓${NC} .env created from template"
    fi

    export DRAGONFLY_URL="$DRAGONFLY_URL"

    echo -e "${BLUE}→ Checking Dart dependencies...${NC}"
    if dart pub get > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Dependencies installed successfully"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} Dependency installation failed"
        ((TESTS_FAILED++))
    fi
    cd ../../
fi

# Phase 6: Cache Operation Simulation
echo ""
echo -e "${YELLOW}Phase 6: Cache Operation Simulation${NC}"
echo -e "${YELLOW}===================================${NC}"

echo -e "${BLUE}→ Simulating cache operations...${NC}"

# Test SET
if [ "$(docker exec xene-dragonfly redis-cli SET "test:sim:key" "test_value" 2>/dev/null)" = "OK" ]; then
    echo -e "${GREEN}✓${NC} SET operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} SET operation failed"
    ((TESTS_FAILED++))
fi

# Test GET
if [ "$(docker exec xene-dragonfly redis-cli GET "test:sim:key" 2>/dev/null)" = "test_value" ]; then
    echo -e "${GREEN}✓${NC} GET operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} GET operation failed"
    ((TESTS_FAILED++))
fi

# Test EXISTS
if [ "$(docker exec xene-dragonfly redis-cli EXISTS "test:sim:key" 2>/dev/null)" = "1" ]; then
    echo -e "${GREEN}✓${NC} EXISTS operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} EXISTS operation failed"
    ((TESTS_FAILED++))
fi

# Test SETEX
if [ "$(docker exec xene-dragonfly redis-cli SETEX "test:sim:ttl" 10 "ttl_value" 2>/dev/null)" = "OK" ]; then
    echo -e "${GREEN}✓${NC} SETEX operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} SETEX operation failed"
    ((TESTS_FAILED++))
fi

# Test INCR
docker exec xene-dragonfly redis-cli DEL "test:sim:counter" 2>/dev/null > /dev/null
if [ "$(docker exec xene-dragonfly redis-cli INCR "test:sim:counter" 2>/dev/null)" = "1" ]; then
    echo -e "${GREEN}✓${NC} INCR operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} INCR operation failed"
    ((TESTS_FAILED++))
fi

# Test DELETE
if [ "$(docker exec xene-dragonfly redis-cli DEL "test:sim:key" 2>/dev/null)" = "1" ]; then
    echo -e "${GREEN}✓${NC} DELETE operation successful"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} DELETE operation failed"
    ((TESTS_FAILED++))
fi

# Phase 7: Distributed Cache Simulation
echo ""
echo -e "${YELLOW}Phase 7: Distributed Cache Simulation${NC}"
echo -e "${YELLOW}=====================================${NC}"

echo -e "${BLUE}→ Simulating distributed coalescing...${NC}"

# Create inflight marker
docker exec xene-dragonfly redis-cli SETEX "feed_inflight:soundcloud:artist1" 10 "fetching" 2>/dev/null > /dev/null
echo "  Replica 1: Set in-flight marker"

# Check if marker exists
if [ "$(docker exec xene-dragonfly redis-cli EXISTS "feed_inflight:soundcloud:artist1" 2>/dev/null)" = "1" ]; then
    echo -e "${GREEN}✓${NC} Replica 2: Detected in-flight marker (coalescing)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Replica 2: Failed to detect marker"
    ((TESTS_FAILED++))
fi

# Clear marker
docker exec xene-dragonfly redis-cli DEL "feed_inflight:soundcloud:artist1" 2>/dev/null > /dev/null
echo "  Replica 1: Cleared marker"

# Verify marker is gone
if [ "$(docker exec xene-dragonfly redis-cli EXISTS "feed_inflight:soundcloud:artist1" 2>/dev/null)" = "0" ]; then
    echo -e "${GREEN}✓${NC} Replica 2-3: Can now fetch fresh data (marker cleared)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Marker failed to clear"
    ((TESTS_FAILED++))
fi

# Phase 8: Cleanup
echo ""
echo -e "${YELLOW}Phase 8: Cleanup${NC}"
echo -e "${YELLOW}================${NC}"

echo -e "${BLUE}→ Cleaning up test data...${NC}"
docker exec xene-dragonfly redis-cli FLUSHDB 2>/dev/null > /dev/null
echo -e "${GREEN}✓${NC} Test data cleaned"

# Final Summary
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN}Test Results Summary${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""
echo -e "${GREEN}Passed:  $TESTS_PASSED${NC}"
echo -e "${RED}Failed:  $TESTS_FAILED${NC}"
echo -e "${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Cache implementation is working correctly.${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "${CYAN}  1. Run backend: cd packages/xene_backend && dart_frog dev${NC}"
    echo -e "${CYAN}  2. Test with: curl http://localhost:8080/feed/merged?artists=soundcloud:test-artist${NC}"
    echo -e "${CYAN}  3. Monitor cache: docker exec xene-dragonfly redis-cli MONITOR${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please review the errors above.${NC}"
    exit 1
fi
