# Brand assets

`flx-icon.svg` and `flx-banner.svg` are the masters; every PNG here is a render
of one of them, so edit the SVG and re-render — never touch a PNG by hand.

| File | Used by |
| --- | --- |
| `flx-icon.svg` | Master mark. The wordmark is drawn as geometry, so it needs no font |
| `flx-icon-128.png` | README headers; copied to `tools/vscode-flx/icon.png` for the marketplace |
| `flx-icon-512.png` | Anywhere a large mark is wanted |
| `flx-file-icon.svg` / `-64.png` | The `.flx` file icon; copied to `tools/vscode-flx/icons/flx-file.png`. The Dart mark's silhouette in flx violet — next to `main.dart` it should read as the same family, different language. No lettering: it is drawn at 16px, where letterforms turn to smudges |
| `flx-banner.svg` / `.png` | Header of the root README. The banner's text *is* text, so its font is baked into the PNG |

No SVG rasterizer is assumed. Chrome renders both files exactly as a browser
would, which is the only rendering that matters here:

```bash
render() {  # render <svg> <out.png> <css-width> <css-height> <scale>
  printf '<!doctype html><style>html,body{margin:0;background:transparent}svg{display:block;width:%spx;height:%spx}</style>' "$3" "$4" > /tmp/r.html
  cat "$1" >> /tmp/r.html
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 --force-device-scale-factor="$5" \
    --window-size="$3,$4" --screenshot="$2" "file:///tmp/r.html"
}

render assets/flx-icon.svg      assets/flx-icon-128.png     128  128 1
render assets/flx-icon.svg      assets/flx-icon-512.png     128  128 4
render assets/flx-file-icon.svg assets/flx-file-icon-64.png 128  128 0.5
render assets/flx-banner.svg    assets/flx-banner.png      1000  260 1.5
cp assets/flx-icon-128.png     tools/vscode-flx/icon.png
cp assets/flx-file-icon-64.png tools/vscode-flx/icons/flx-file.png
```

The extension icon must stay exactly 128×128 — that is what the VS Code
marketplace asks for, and `vsce package` checks it.
