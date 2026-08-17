#!/usr/bin/env node
// ============================================================
// flxc — the .flx → Dart transpiler (prototype)
// Usage: node flxc.js input.flx -o output.dart
//
// Supported DSL (v0):
//   import "path"
//   @page("/route")
//   composable Name {
//     val x = expr
//     Widget(named: arg, ...) { children or callback }
//   }
//
// Rules:
// - Trailing { } after a layout widget (Column/Row/Stack/Wrap)
//   = children. After any other widget = callback body.
// - val x = useFetch(...) auto-generates loading/error handling
//   via AsyncValue.when, and `x` is the unwrapped data inside UI.
// - style: .title  →  Styles.title
// - main: .center  →  MainAxisAlignment.center
// ============================================================

'use strict';

const fs = require('fs');

// ---------------- Tokenizer ----------------

function tokenize(src) {
  const tokens = [];
  let i = 0;
  const isIdStart = (c) => /[A-Za-z_$]/.test(c);
  const isId = (c) => /[A-Za-z0-9_$]/.test(c);

  while (i < src.length) {
    const c = src[i];
    if (/\s/.test(c)) { i++; continue; }
    if (c === '/' && src[i + 1] === '/') {
      while (i < src.length && src[i] !== '\n') i++;
      continue;
    }
    if (c === '"' || c === "'") {
      const quote = c;
      const start = i;
      i++;
      while (i < src.length) {
        if (src[i] === '\\') { i += 2; continue; }
        if (src[i] === quote) { i++; break; }
        i++;
      }
      tokens.push({ type: 'string', value: src.slice(start, i), start, end: i });
      continue;
    }
    if (/[0-9]/.test(c)) {
      const start = i;
      while (i < src.length && /[0-9.]/.test(src[i])) i++;
      tokens.push({ type: 'number', value: src.slice(start, i), start, end: i });
      continue;
    }
    if (isIdStart(c)) {
      const start = i;
      while (i < src.length && isId(src[i])) i++;
      tokens.push({ type: 'ident', value: src.slice(start, i), start, end: i });
      continue;
    }
    const two = src.slice(i, i + 2);
    if (['++', '--', '=>', '==', '!=', '<=', '>=', '&&', '||', '+=', '-=', '?.', '??'].includes(two)) {
      tokens.push({ type: 'punct', value: two, start: i, end: i + 2 });
      i += 2;
      continue;
    }
    tokens.push({ type: 'punct', value: c, start: i, end: i + 1 });
    i++;
  }
  return tokens;
}

// ---------------- Parser ----------------

class Parser {
  constructor(src) {
    this.src = src;
    this.tokens = tokenize(src);
    this.pos = 0;
  }

  peek(offset) { return this.tokens[this.pos + (offset || 0)] || null; }
  next() { return this.tokens[this.pos++]; }

  expect(value, type) {
    const t = this.next();
    if (!t || (value != null && t.value !== value) || (type != null && t.type !== type)) {
      const got = t ? t.type + " '" + t.value + "'" : 'end of file';
      throw new Error('flxc: expected ' + (value || type) + ' but got ' + got);
    }
    return t;
  }

  parseFile() {
    const imports = [];
    while (this.peek() && this.peek().type === 'ident' && this.peek().value === 'import') {
      this.next();
      imports.push(this.expect(null, 'string').value);
    }
    const annotations = [];
    while (this.peek() && this.peek().value === '@') {
      this.next();
      const name = this.expect(null, 'ident').value;
      this.expect('(');
      const arg = this.expect(null, 'string').value;
      this.expect(')');
      annotations.push({ name, arg });
    }
    this.expect('composable');
    const name = this.expect(null, 'ident').value;
    const params = [];
    if (this.peek() && this.peek().value === '(') {
      this.next();
      while (this.peek() && this.peek().value !== ')') {
        const pname = this.expect(null, 'ident').value;
        let ptype = 'String';
        if (this.peek() && this.peek().value === ':') {
          this.next();
          ptype = this.expect(null, 'ident').value;
        }
        params.push({ name: pname, type: ptype });
        if (this.peek() && this.peek().value === ',') this.next();
      }
      this.expect(')');
    }
    this.expect('{');
    const vals = [];
    while (this.peek() && this.peek().value === 'val') {
      this.next();
      const vname = this.expect(null, 'ident').value;
      this.expect('=');
      vals.push({ name: vname, tokens: this.captureExpr() });
    }
    const root = this.parseWidget();
    this.expect('}');
    return { imports, annotations, name, params, vals, root };
  }

  // Capture a chained expression: ident(.ident | (...) | [...])*
  captureExpr() {
    const out = [];
    let t = this.next();
    out.push(t);
    if (t.value === '.') out.push(this.next()); // .shorthand
    for (;;) {
      const p = this.peek();
      if (!p) break;
      if (p.value === '.') { out.push(this.next()); out.push(this.next()); continue; }
      if (p.value === '(') { this.captureBalanced('(', ')', out); continue; }
      if (p.value === '[') { this.captureBalanced('[', ']', out); continue; }
      if (['+', '-', '*', '/', '??', '?.'].includes(p.value)) {
        out.push(this.next());
        out.push(this.next());
        continue;
      }
      break;
    }
    return out;
  }

  captureBalanced(open, close, out) {
    let depth = 0;
    do {
      const t = this.next();
      if (!t) throw new Error('flxc: unbalanced ' + open);
      if (t.value === open) depth++;
      if (t.value === close) depth--;
      out.push(t);
    } while (depth > 0);
  }

  parseWidget() {
    const nameTok = this.expect(null, 'ident');
    const w = { name: nameTok.value, args: [], children: null, callback: null };
    if (this.peek() && this.peek().value === '(') {
      this.next(); // consume (
      while (this.peek() && this.peek().value !== ')') {
        w.args.push(this.parseArg());
        if (this.peek() && this.peek().value === ',') this.next();
      }
      this.expect(')');
    }
    if (this.peek() && this.peek().value === '{') {
      // Deterministic rule: layout widgets take children, everything else a callback.
      if (LAYOUTS[w.name]) {
        this.next(); // {
        w.children = [];
        while (this.peek() && this.peek().value !== '}') {
          w.children.push(this.parseChild());
        }
        this.expect('}');
      } else {
        // callback: slice raw source between the braces
        const openTok = this.next(); // {
        let depth = 1;
        let lastEnd = openTok.end;
        while (depth > 0) {
          const t = this.next();
          if (!t) throw new Error('flxc: unbalanced { in callback');
          if (t.value === '{') depth++;
          if (t.value === '}') depth--;
          if (depth > 0) lastEnd = t.end;
          else w.callback = this.src.slice(openTok.end, t.start);
        }
      }
    }
    return w;
  }

  parseChild() {
    const p = this.peek();
    if (p && p.type === 'ident' && p.value === 'if') return this.parseIf();
    if (p && p.type === 'ident' && p.value === 'for') return this.parseFor();
    return this.parseWidget();
  }

  parseIf() {
    this.expect('if');
    const condRaw = [];
    this.captureBalanced('(', ')', condRaw);
    const cond = condRaw.slice(1, -1);
    this.expect('{');
    const then = [];
    while (this.peek() && this.peek().value !== '}') {
      then.push(this.parseChild());
    }
    this.expect('}');
    let elseChildren = null;
    if (this.peek() && this.peek().value === 'else') {
      this.next();
      if (this.peek() && this.peek().value === 'if') {
        elseChildren = [this.parseIf()];
      } else {
        this.expect('{');
        elseChildren = [];
        while (this.peek() && this.peek().value !== '}') {
          elseChildren.push(this.parseChild());
        }
        this.expect('}');
      }
    }
    return { kind: 'if', cond, then, elseChildren };
  }

  parseFor() {
    this.expect('for');
    this.expect('(');
    const varName = this.expect(null, 'ident').value;
    this.expect('in');
    const listTokens = [];
    let depth = 0;
    for (;;) {
      const p = this.peek();
      if (!p) throw new Error('flxc: unterminated for(...)');
      if (depth === 0 && p.value === ')') break;
      const t = this.next();
      if (t.value === '(' || t.value === '[' || t.value === '{') depth++;
      if (t.value === ')' || t.value === ']' || t.value === '}') depth--;
      listTokens.push(t);
    }
    this.expect(')');
    this.expect('{');
    const children = [];
    while (this.peek() && this.peek().value !== '}') {
      children.push(this.parseChild());
    }
    this.expect('}');
    return { kind: 'for', varName, listTokens, children };
  }

  parseArg() {
    // named if: ident ':' (and ':' is the separator, not part of expr)
    const a = { name: null, tokens: [] };
    if (this.peek() && this.peek().type === 'ident' && this.peek(1) && this.peek(1).value === ':') {
      a.name = this.next().value;
      this.next(); // :
    }
    // capture until , or ) at depth 0
    let depth = 0;
    for (;;) {
      const p = this.peek();
      if (!p) throw new Error('flxc: unterminated argument list');
      if (depth === 0 && (p.value === ',' || p.value === ')')) break;
      const t = this.next();
      if (t.value === '(' || t.value === '[' || t.value === '{') depth++;
      if (t.value === ')' || t.value === ']' || t.value === '}') depth--;
      a.tokens.push(t);
    }
    return a;
  }
}

// ---------------- Serialization ----------------

const TIGHT_BEFORE = new Set(['.', ',', ')', ']', '(', '[', '++', '--', '?.']);
const TIGHT_AFTER = new Set(['.', '(', '[', '!', '?.']);

function ser(tokens) {
  let out = '';
  let prev = null;
  for (const t of tokens) {
    if (prev) {
      const noSpace = TIGHT_BEFORE.has(t.value) || TIGHT_AFTER.has(prev.value);
      if (!noSpace) out += ' ';
      if (prev.value === ',') out = out.slice(0, -1) + ' '; // ", " style
    }
    out += t.value;
    prev = t;
  }
  return out;
}

const ENUM_ARGS = { main: 'MainAxisAlignment', cross: 'CrossAxisAlignment' };

function serArg(a) {
  const raw = ser(a.tokens);
  if (raw.startsWith('.')) {
    if (a.name === 'style') return 'Styles' + raw;
    if (ENUM_ARGS[a.name]) return ENUM_ARGS[a.name] + raw;
  }
  return raw;
}

// ---------------- Code generation ----------------

const LAYOUTS = { Column: 'column', Row: 'row', Stack: 'stack', Wrap: 'wrap' };
const MODIFIER_ARGS = new Set(['padding', 'background', 'center', 'safeArea']);

function genWidget(w, indent) {
  const pad = ' '.repeat(indent);
  if (LAYOUTS[w.name]) {
    const layoutArgs = [];
    const modifiers = [];
    for (const a of w.args) {
      if (!a.name) continue;
      if (MODIFIER_ARGS.has(a.name)) {
        modifiers.push('.' + a.name + '(' + serArg(a) + ')');
      } else {
        layoutArgs.push(a.name + ': ' + serArg(a));
      }
    }
    const kids = (w.children || [])
      .map((c) => genChild(c, indent + 2))
      .join(',\n');
    let s = pad + '[\n' + kids + ',\n' + pad + '].' + LAYOUTS[w.name] + '(' + layoutArgs.join(', ') + ')';
    for (const m of modifiers) s += m;
    return s;
  }

  const argStrs = w.args.map((a) => (a.name ? a.name + ': ' + serArg(a) : ser(a.tokens)));
  if (w.callback != null) {
    const body = formatCallback(w.callback, indent + 2);
    argStrs.push('() {\n' + body + '\n' + pad + '}');
  }
  return pad + w.name + '(' + argStrs.join(', ') + ')';
}

function genChild(node, indent) {
  const pad = ' '.repeat(indent);
  if (node.kind === 'if') {
    let s =
      pad + 'if (' + ser(node.cond) + ') ...[\n' +
      node.then.map((c) => genChild(c, indent + 2)).join(',\n') + ',\n' +
      pad + ']';
    if (node.elseChildren) {
      if (node.elseChildren.length === 1 && node.elseChildren[0].kind === 'if') {
        s += ' else ' + genChild(node.elseChildren[0], indent).trimStart();
      } else {
        s +=
          ' else ...[\n' +
          node.elseChildren.map((c) => genChild(c, indent + 2)).join(',\n') + ',\n' +
          pad + ']';
      }
    }
    return s;
  }
  if (node.kind === 'for') {
    return (
      pad + 'for (final ' + node.varName + ' in ' + ser(node.listTokens) + ') ...[\n' +
      node.children.map((c) => genChild(c, indent + 2)).join(',\n') + ',\n' +
      pad + ']'
    );
  }
  return genWidget(node, indent);
}

function formatCallback(raw, indent) {
  const pad = ' '.repeat(indent);
  return raw
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .map((l) => {
      const needsSemi = !/[;{}]$/.test(l);
      return pad + l + (needsSemi ? ';' : '');
    })
    .join('\n');
}

function generate(ast, flxFileName) {
  const lines = [];
  lines.push('// GENERATED by flxc from ' + flxFileName + ' — do not edit by hand.');
  lines.push("import 'package:flutter/material.dart';");
  lines.push('');
  lines.push("import '../clean_ui/clean_ui.dart';");
  for (const imp of ast.imports) {
    lines.push('import ' + imp.replace(/"/g, "'") + ';');
  }
  lines.push('');

  const isPage = ast.annotations.some((a) => a.name === 'page');
  for (const ann of ast.annotations) {
    if (ann.name === 'page') {
      lines.push('@page(' + ann.arg.replace(/"/g, "'") + ')');
    }
  }

  lines.push('class ' + ast.name + ' extends Composable {');
  if (ast.params.length > 0) {
    const ctorArgs = ast.params.map((p) => 'required this.' + p.name).join(', ');
    lines.push('  const ' + ast.name + '({' + ctorArgs + ', super.key});');
    for (const p of ast.params) {
      lines.push('  final ' + p.type + ' ' + p.name + ';');
    }
  } else {
    lines.push('  const ' + ast.name + '({super.key});');
  }
  lines.push('');
  lines.push('  @override');
  lines.push('  Widget build(BuildContext context) {');

  const asyncVals = [];
  for (const v of ast.vals) {
    const expr = ser(v.tokens);
    if (expr.startsWith('useFetch(')) {
      asyncVals.push(v.name);
      lines.push('    final ' + v.name + '$ = ' + expr + ';');
    } else {
      lines.push('    final ' + v.name + ' = ' + expr + ';');
    }
  }
  lines.push('');

  // Build the root as an expression, innermost first.
  let expr = genWidget(ast.root, 6).trimStart();

  // Wrap in .when() for each useFetch val (reverse order → outermost first)
  for (let i = asyncVals.length - 1; i >= 0; i--) {
    const name = asyncVals[i];
    expr =
      name + '$.when(\n' +
      '      loading: () => const Center(child: CircularProgressIndicator()),\n' +
      "      error: (error) => Center(child: Text('Error: " + '$' + "error')),\n" +
      '      data: (' + name + ') {\n' +
      '        return ' + expr + ';\n' +
      '      },\n' +
      '    )';
  }

  // @page composables are screens — auto-wrap them in a Scaffold.
  if (isPage) {
    expr = 'Scaffold(\n      body: ' + expr + ',\n    )';
  }

  lines.push('    return ' + expr + ';');
  lines.push('  }');
  lines.push('}');
  lines.push('');
  return lines.join('\n');
}

// ---------------- CLI ----------------

function generateRoutes(pages) {
  const lines = [];
  lines.push('// GENERATED by flxc — route table. Do not edit by hand.');
  lines.push("import '../clean_ui/clean_ui.dart';");
  lines.push('');
  for (const p of pages) {
    lines.push("import '" + p.file + "';");
  }
  lines.push('');
  lines.push('final appRoutes = <RouteDef>[');
  for (const p of pages) {
    if (p.params.length === 0) {
      lines.push("  RouteDef('" + p.path + "', (params) => const " + p.className + '()),');
    } else {
      const args = p.params
        .map((pr) => pr.name + ": params['" + pr.name + "'] ?? ''")
        .join(', ');
      lines.push("  RouteDef('" + p.path + "', (params) => " + p.className + '(' + args + ')),');
    }
  }
  lines.push('];');
  lines.push('');
  return lines.join('\n');
}

function transpileFile(input, output) {
  const src = fs.readFileSync(input, 'utf8');
  const ast = new Parser(src).parseFile();
  const dart = generate(ast, input.split('/').pop());
  fs.writeFileSync(output, dart);
  console.log('flxc: ' + input + ' -> ' + output);
  return ast;
}

function main() {
  const args = process.argv.slice(2);
  if (!args[0]) {
    console.error('Usage:\n  node flxc.js build [pagesDir]\n  node flxc.js input.flx [-o output.dart]');
    process.exit(1);
  }

  // Build mode: transpile every .flx in the dir + generate routes.g.dart
  if (args[0] === 'build') {
    const dir = args[1] || 'lib/pages';
    const pages = [];
    for (const f of fs.readdirSync(dir).sort()) {
      if (!f.endsWith('.flx')) continue;
      const input = dir + '/' + f;
      const output = input.replace(/\.flx$/, '.dart');
      const ast = transpileFile(input, output);
      const pageAnn = ast.annotations.find((a) => a.name === 'page');
      if (pageAnn) {
        pages.push({
          file: f.replace(/\.flx$/, '.dart'),
          path: pageAnn.arg.slice(1, -1),
          className: ast.name,
          params: ast.params,
        });
      }
    }
    const routesPath = dir + '/routes.g.dart';
    fs.writeFileSync(routesPath, generateRoutes(pages));
    console.log('flxc: generated ' + routesPath + ' (' + pages.length + ' routes)');
    return;
  }

  // Single-file mode
  const input = args[0];
  const oIndex = args.indexOf('-o');
  const output = oIndex >= 0 ? args[oIndex + 1] : input.replace(/\.flx$/, '.dart');
  transpileFile(input, output);
}

main();
