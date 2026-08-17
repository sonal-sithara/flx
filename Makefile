.PHONY: help setup build watch test analyze run run-example clean ci

FLXC    := dart run packages/flxc/bin/flxc.dart
LEDGER  := apps/ledger/lib/pages
EXAMPLE := example/lib/pages
PAGE_DIRS := $(LEDGER) $(EXAMPLE)

help:
	@echo "flx — development commands"
	@echo ""
	@echo "  make setup       Fetch dependencies for every package"
	@echo "  make build       Transpile every .flx and regenerate routes"
	@echo "  make watch       Rebuild Ledger's pages on every save"
	@echo "  make test        Run all tests (compiler, runtime, both apps)"
	@echo "  make analyze     Analyze every package"
	@echo "  make run         Build, then launch Ledger"
	@echo "  make run-example Build, then launch the framework demo"
	@echo "  make ci          analyze + build + stale-codegen check + test"
	@echo "  make clean       Remove generated Dart and build output"

setup:
	cd packages/flxc && dart pub get
	cd packages/flx  && flutter pub get
	cd example       && flutter pub get
	cd apps/ledger   && flutter pub get

build:
	@$(foreach dir,$(PAGE_DIRS),$(FLXC) build $(dir);)

watch:
	@$(FLXC) watch $(LEDGER)

test:
	cd packages/flxc && dart test
	cd packages/flx  && flutter test
	cd example       && flutter test
	cd apps/ledger   && flutter test

analyze:
	cd packages/flxc && dart analyze
	cd packages/flx  && flutter analyze
	cd example       && flutter analyze
	cd apps/ledger   && flutter analyze

# A dirty tree after `build` means someone committed a .dart without
# regenerating it from its .flx.
ci: analyze build
	@git diff --exit-code -- $(PAGE_DIRS) \
		|| (echo "generated Dart is stale — run 'make build' and commit"; exit 1)
	@$(MAKE) test

run: build
	cd apps/ledger && flutter run

run-example: build
	cd example && flutter run

clean:
	rm -f $(LEDGER)/*.dart $(EXAMPLE)/*.dart
	cd apps/ledger   && flutter clean
	cd example       && flutter clean
	cd packages/flx  && flutter clean
