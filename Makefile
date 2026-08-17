.PHONY: help setup build watch test analyze run clean ci lsp lsp-build

FLXC   := dart run packages/flxc/bin/flxc.dart
PAGES  := apps/ledger/lib/pages
INTEROP := apps/interop/lib/pages

help:
	@echo "flx — development commands"
	@echo ""
	@echo "  make setup     Fetch dependencies for every package"
	@echo "  make build     Transpile every .flx and regenerate routes"
	@echo "  make watch     Rebuild on every save"
	@echo "  make test      Run all tests (compiler, runtime, app)"
	@echo "  make analyze   Analyze every package"
	@echo "  make run       Build, then launch Ledger"
	@echo "  make lsp       Run the language server (editors do this for you)"
	@echo "  make lsp-build Compile the language server to a native binary"
	@echo "  make ci        analyze + build + stale-codegen check + test"
	@echo "  make clean     Remove generated Dart and build output"

setup:
	cd packages/flxc    && dart pub get
	cd packages/flx_lsp && dart pub get
	cd packages/flx     && flutter pub get
	cd apps/ledger      && flutter pub get
	cd apps/interop     && flutter pub get

build:
	@$(FLXC) build $(PAGES)
	@$(FLXC) build $(INTEROP)

watch:
	@$(FLXC) watch $(PAGES)

test:
	cd packages/flxc    && dart test
	cd packages/flx_lsp && dart test
	cd packages/flx     && flutter test
	cd apps/ledger      && flutter test

analyze:
	cd packages/flxc    && dart analyze
	cd packages/flx_lsp && dart analyze
	cd packages/flx     && flutter analyze
	cd apps/ledger      && flutter analyze
	cd apps/interop     && flutter analyze
	@$(FLXC) analyze $(PAGES)

lsp:
	cd packages/flx_lsp && dart run bin/flx_lsp.dart

# A compiled server starts in milliseconds instead of seconds. Point
# flx.server.path at the result.
lsp-build:
	@mkdir -p packages/flx_lsp/build
	cd packages/flx_lsp && dart compile exe bin/flx_lsp.dart -o build/flx_lsp
	@echo "built packages/flx_lsp/build/flx_lsp"

# A dirty tree after `build` means someone committed a .dart without
# regenerating it from its .flx.
ci: analyze build
	@git diff --exit-code -- $(PAGES) $(INTEROP) \
		|| (echo "generated Dart is stale — run 'make build' and commit"; exit 1)
	@$(MAKE) test

run: build
	cd apps/ledger && flutter run

clean:
	rm -f $(PAGES)/*.dart $(INTEROP)/*.dart
	rm -rf packages/flx_lsp/build
	cd apps/ledger  && flutter clean
	cd packages/flx && flutter clean
