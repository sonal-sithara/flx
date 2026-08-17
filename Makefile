.PHONY: help setup build watch test analyze run clean ci

FLXC := dart run packages/flxc/bin/flxc.dart
PAGES := example/lib/pages

help:
	@echo "flx — development commands"
	@echo ""
	@echo "  make setup     Fetch dependencies for every package"
	@echo "  make build     Transpile .flx -> .dart and regenerate routes"
	@echo "  make watch     Rebuild on every .flx save"
	@echo "  make test      Run all tests (compiler, runtime, example app)"
	@echo "  make analyze   Analyze every package"
	@echo "  make run       Build, then launch the example app"
	@echo "  make ci        analyze + build --check + test"
	@echo "  make clean     Remove generated Dart and build output"

setup:
	cd packages/flxc && dart pub get
	cd packages/flx && flutter pub get
	cd example && flutter pub get

build:
	@$(FLXC) build $(PAGES)

watch:
	@$(FLXC) watch $(PAGES)

# `check` transpiles without writing — a dirty tree in CI means someone
# committed a .dart without regenerating it from its .flx.
ci: analyze
	@$(FLXC) build $(PAGES)
	@git diff --exit-code -- '$(PAGES)' \
		|| (echo "generated Dart is stale — run 'make build' and commit"; exit 1)
	@$(MAKE) test

test:
	cd packages/flxc && dart test
	cd packages/flx && flutter test
	cd example && flutter test

analyze:
	cd packages/flxc && dart analyze
	cd packages/flx && flutter analyze
	cd example && flutter analyze

run: build
	cd example && flutter run

clean:
	rm -f $(PAGES)/*.dart
	cd example && flutter clean
	cd packages/flx && flutter clean
