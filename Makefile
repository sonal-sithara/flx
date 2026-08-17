.PHONY: help setup build watch test analyze run clean ci

FLXC   := dart run packages/flxc/bin/flxc.dart
PAGES  := apps/ledger/lib/pages

help:
	@echo "flx — development commands"
	@echo ""
	@echo "  make setup     Fetch dependencies for every package"
	@echo "  make build     Transpile every .flx and regenerate routes"
	@echo "  make watch     Rebuild on every save"
	@echo "  make test      Run all tests (compiler, runtime, app)"
	@echo "  make analyze   Analyze every package"
	@echo "  make run       Build, then launch Ledger"
	@echo "  make ci        analyze + build + stale-codegen check + test"
	@echo "  make clean     Remove generated Dart and build output"

setup:
	cd packages/flxc && dart pub get
	cd packages/flx  && flutter pub get
	cd apps/ledger   && flutter pub get

build:
	@$(FLXC) build $(PAGES)

watch:
	@$(FLXC) watch $(PAGES)

test:
	cd packages/flxc && dart test
	cd packages/flx  && flutter test
	cd apps/ledger   && flutter test

analyze:
	cd packages/flxc && dart analyze
	cd packages/flx  && flutter analyze
	cd apps/ledger   && flutter analyze

# A dirty tree after `build` means someone committed a .dart without
# regenerating it from its .flx.
ci: analyze build
	@git diff --exit-code -- $(PAGES) \
		|| (echo "generated Dart is stale — run 'make build' and commit"; exit 1)
	@$(MAKE) test

run: build
	cd apps/ledger && flutter run

clean:
	rm -f $(PAGES)/*.dart
	cd apps/ledger  && flutter clean
	cd packages/flx && flutter clean
