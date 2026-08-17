# Publishing handoff

Everything that could be done without an account or a remote is done. What
remains needs credentials only you have.

Work through this top to bottom; each step assumes the ones above it.

---

## 0. Replace the placeholder repository URL

Every package points at `https://github.com/sonal-sithara/flx`, which is a
guess derived from your email. If your GitHub account or repository name
differs, fix it before anything else — pub.dev records it permanently on the
listing.

```bash
grep -rln 'github.com/sonalsithara/flx' \
  packages/*/pubspec.yaml packages/*/README.md packages/*/CHANGELOG.md \
  tools/vscode-flx/package.json
```

Replace in all of them, then re-run `make ci`.

---

## 1. Create the repository and push

```bash
gh repo create flx --public --source=. --remote=origin --push
# or, by hand:
#   git remote add origin git@github.com:<you>/flx.git
#   git push -u origin main
```

CI runs on the first push: `.github/workflows/ci.yml` analyzes every package,
transpiles every `.flx`, fails if committed Dart is stale relative to its
source, runs all 343 tests, and builds Ledger for web and macOS.

**Check it goes green before continuing.** The workflows have never run —
they are written against `make`, which does work locally, but CI runners
differ.

---

## 2. Publish the Dart packages

Order matters: `flx_lsp` depends on `flx_compiler` by version, so
`flx_compiler` must exist on pub.dev first.

```bash
dart pub login          # once

cd packages/flx_compiler && dart pub publish
cd ../flx_runtime        && flutter pub publish
cd ../flx_lsp            && dart pub publish
```

`--dry-run` is clean on all three. Between publishing `flx_compiler` and
`flx_lsp`, pub.dev needs a minute to index.

**Names.** The three packages are `flx_runtime`, `flx_compiler` and `flx_lsp`.
The command is still `flxc` — `dart pub global activate flx_compiler` installs
it, because the command name comes from `bin/flxc.dart` rather than from the
package. The project, the DSL and the `.flx` extension are all still flx.

`flx` itself belongs to an unrelated 2018 package for Flutter's old bundle
format, and pub.dev never reclaims names, which is the whole reason the
packages carry a suffix.

`packages/flx_lsp/pubspec_overrides.yaml` keeps local builds pointing at the
sibling directory. Pub ignores it when publishing, so it does not need
removing.

---

## 3. Release the VS Code extension

Tag a version and the release workflow does the rest:

```bash
git tag v0.2.0 && git push --tags
```

`.github/workflows/release.yml` compiles `flx_lsp` for darwin-arm64,
darwin-x64, linux-x64 and win32-x64, packages one VSIX per platform with the
matching binary inside, and attaches all four to the GitHub release.

That is enough for people to install by hand:

```bash
code --install-extension flx-darwin-arm64.vsix
```

### For the Marketplace as well

1. Create an Azure DevOps organisation, then a Marketplace publisher at
   <https://marketplace.visualstudio.com/manage>.
2. Set `"publisher"` in `tools/vscode-flx/package.json` to that publisher ID —
   it is currently `flx`, which is almost certainly not yours.
3. Create a Personal Access Token with **Marketplace → Manage** scope.
4. Add it as the repository secret `VSCE_PAT`.
5. Append a publish step to the `extension` job:

```yaml
- name: Publish
  if: startsWith(github.ref, 'refs/tags/v')
  working-directory: tools/vscode-flx
  run: npx --yes @vscode/vsce publish --target ${{ matrix.target }} --pat $VSCE_PAT
  env:
    VSCE_PAT: ${{ secrets.VSCE_PAT }}
```

Also worth adding before the first Marketplace release: a 128×128 `icon.png`
and an `icon` field in `package.json`. Listings without one look abandoned.

---

## What is untested, and will bite first

**The workflows have never run.** Both are plausible and neither is proven —
in particular the `extension` job needs `xvfb` on Linux, which is written in
but unverified.

**`vsce package` has never run here.** Expect it to complain about a missing
icon, repository field, or LICENSE reference on the first attempt.

The extension client itself _is_ tested now:

```bash
make vscode-test
```

launches a real VS Code with the extension loaded and drives it through eight
assertions — activation, diagnostics arriving and clearing, completion in a
binding and in a children block, hover, go-to-definition and the outline. That
found one bug the unit tests could not: go-to-definition preferred whichever
same-named composable the workspace index happened to hash first, so jumping
to a `Badge` declared in the open file could land in an unrelated one.

To use it day to day rather than test it:

```bash
npm install --prefix tools/vscode-flx
ln -s "$PWD/tools/vscode-flx" ~/.vscode/extensions/flx
```

---

## After publishing

- `dart pub publish` is irreversible. A published version can be retracted but
  never replaced, so let CI go green first.
- pub.dev scores packages within an hour. Expect points off for the API being
  new and for example coverage.
- Version numbers are all `0.2.0`, packages and extension alike. Below 1.0,
  semver treats every minor bump as potentially breaking, which is honest for
  where this is.
