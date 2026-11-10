# Local checks, the same ones CI runs (.github/workflows/ci.yml). `make` on its own lists the targets.
# Needs Xcode, plus `brew install swiftlint swiftformat jq` for lint and the simulator pick.

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT      := photo-swiper/photo-swiper.xcodeproj
SCHEME       := photo-swiper
# In the repo (build/ is ignored), so each worktree builds incrementally without sharing Xcode's DerivedData.
DERIVED_DATA ?= $(CURDIR)/build/DerivedData
LOGS         := $(CURDIR)/build/logs
# The first available iPhone, as in CI. Override with DEST='platform=iOS Simulator,name=iPhone 16'.
DEST         ?= $(shell scripts/sim-destination.sh)
# The branch that `lint` and `format` compare against.
BASE         ?= origin/main
# WARNINGS=1 shows compiler warnings in `build` (CI sets it). LINT_STRICT=1 makes `lint` fail on findings.
WARNINGS     ?= 0
LINT_STRICT  ?= 0
# Extra linter flags; CI passes its annotation reporters here.
LINT_ARGS_FORMAT ?=
LINT_ARGS_LINT   ?=

# macOS ships GNU Make 3.81, which ignores .SHELLFLAGS, so piped recipes set pipefail themselves.
PIPEFAIL := set -o pipefail;

XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath '$(DERIVED_DATA)'

# CI skips these; they only work on a real Mac (docs/ci.md says why). The one list, used by every target that needs it.
SKIP_CI := -skip-testing:photo-swiperTests/ScalingTests \
           -skip-testing:photo-swiperTests/StoreKitEntitlementStoreTests \
           '-skip-testing:photo-swiperTests/FeaturePrintTests/distanceMatchesVision()'

# Output filters: failures and the final summary, not every passing test.
ifeq ($(WARNINGS),1)
BUILD_FILTER := warning:|error:|\*\* .*(SUCCEEDED|FAILED)
else
BUILD_FILTER := error:|\*\* .*(SUCCEEDED|FAILED)
endif
TEST_FILTER := ✘|error:|Test Case .* failed|Executed [0-9]+ tests?, with|Test run with|\*\* TEST .*(SUCCEEDED|FAILED)

# Changed Swift files against BASE: committed, uncommitted and untracked.
CHANGED = { git diff --name-only --diff-filter=ACMR "$$(git merge-base $(BASE) HEAD)" -- '*.swift'; \
            git ls-files --others --exclude-standard -- '*.swift'; } | grep -v '^photo-swiper-context/' | sort -u

.PHONY: help build test-unit test-all-unit test-ui test-scaling lint lint-all format analyze verify clean check-dest

help: ## List the targets
	@echo "Usage: make <target>   (needs Xcode; brew install swiftlint swiftformat jq)"
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  %-14s %s\n", $$1, $$2 }'

check-dest:
	@test -n "$(DEST)" || { echo "No simulator destination. Set DEST='platform=iOS Simulator,name=…'." >&2; exit 1; }

build: check-dest ## Incremental build of the app and test targets; prints errors only (log: build/logs/build.log)
	@mkdir -p $(LOGS)
	@$(PIPEFAIL) $(XCB) build-for-testing 2>&1 | tee $(LOGS)/build.log | { grep -E "$(BUILD_FILTER)" || true; }

test-unit: build ## Unit tests exactly as CI runs them (skips the three Mac-only tests)
	@$(PIPEFAIL) $(XCB) test-without-building -only-testing:photo-swiperTests $(SKIP_CI) 2>&1 \
		| tee $(LOGS)/test-unit.log | { grep -E "$(TEST_FILTER)" || true; } | uniq

test-all-unit: build ## Every unit test, no skips (real Mac only; StoreKit tests can flake)
	@$(PIPEFAIL) $(XCB) test-without-building -only-testing:photo-swiperTests 2>&1 \
		| tee $(LOGS)/test-all-unit.log | { grep -E "$(TEST_FILTER)" || true; } | uniq

test-ui: build ## UI tests, serially (slow, ~15 min; run with nothing else building)
	@$(PIPEFAIL) $(XCB) test-without-building -parallel-testing-enabled NO -only-testing:photo-swiperUITests 2>&1 \
		| tee $(LOGS)/test-ui.log | { grep -E "$(TEST_FILTER)" || true; } | uniq

test-scaling: build ## Only ScalingTests (50k synthetic items; timings in build/logs/test-scaling.log)
	@$(PIPEFAIL) $(XCB) test-without-building -only-testing:photo-swiperTests/ScalingTests 2>&1 \
		| tee $(LOGS)/test-scaling.log | { grep -E "$(TEST_FILTER)" || true; } | uniq

lint: ## SwiftFormat (lint mode) and SwiftLint on Swift files changed against BASE
	@command -v swiftformat >/dev/null && command -v swiftlint >/dev/null \
		|| { echo "lint: needs swiftformat and swiftlint (brew install swiftlint swiftformat)"; exit $(LINT_STRICT); }
	@files=$$($(CHANGED)); \
	if [ -z "$$files" ]; then echo "lint: no changed Swift files"; exit 0; fi; \
	status=0; \
	echo "$$files" | xargs swiftformat --lint --quiet $(LINT_ARGS_FORMAT) || status=1; \
	echo "$$files" | xargs swiftlint lint --quiet $(LINT_ARGS_LINT) || status=1; \
	if [ $$status -ne 0 ]; then echo "lint: findings above$(if $(filter 1,$(LINT_STRICT)),, (warnings only; LINT_STRICT=1 to fail))"; fi; \
	[ "$(LINT_STRICT)" != 1 ] || exit $$status

lint-all: ## Both linters on the whole tree (informational; never fails)
	-@swiftformat --lint --quiet .
	-@swiftlint lint --quiet

format: ## SwiftFormat on changed Swift files only
	@command -v swiftformat >/dev/null || { echo "format: needs swiftformat (brew install swiftformat)"; exit 1; }
	@files=$$($(CHANGED)); \
	if [ -z "$$files" ]; then echo "format: no changed Swift files"; exit 0; fi; \
	echo "$$files" | xargs swiftformat --quiet

analyze: check-dest ## swiftlint analyze (unused_import) on a fresh, separate build log
	@mkdir -p $(LOGS)
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath '$(DERIVED_DATA)-analyze' \
		clean build > $(LOGS)/analyze-build.log 2>&1 || { tail -20 $(LOGS)/analyze-build.log; exit 1; }
	@swiftlint analyze --quiet --compiler-log-path $(LOGS)/analyze-build.log

verify: lint build test-unit ## What an agent runs before saying "done"

clean: ## Remove build/ (this repo's DerivedData and logs)
	rm -rf build/DerivedData build/DerivedData-analyze build/logs
