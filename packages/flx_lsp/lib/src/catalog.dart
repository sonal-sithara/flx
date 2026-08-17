/// What the server knows about flx: every hook, widget, argument and
/// shorthand, with the documentation shown on hover and completion.
///
/// This is hand-written rather than derived from the runtime, because the
/// useful part — when to reach for a thing, and what goes wrong if you don't —
/// is not recoverable from a signature. `catalog_drift_test.dart` keeps it
/// honest by failing when packages/flx grows a public hook or widget that is
/// not described here.
library;

enum FlxKind {
  hook,
  widget,
  layout,
  container,
  builder,
  keyword,
  modifier,
  shorthand,
}

class FlxSymbol {
  const FlxSymbol(
    this.name,
    this.kind,
    this.signature,
    this.documentation, {
    this.snippet,
  });

  final String name;
  final FlxKind kind;

  /// Rendered as Dart in the hover card.
  final String signature;
  final String documentation;

  /// LSP snippet syntax. Falls back to the bare name.
  final String? snippet;

  String get insertText => snippet ?? name;
}

const hooks = <FlxSymbol>[
  FlxSymbol('useState', FlxKind.hook, 'StateRef<T> useState<T>(T initial)',
      'Reactive state. Assigning `.value` rebuilds the composable; assigning '
      'an equal value does nothing.',
      snippet: r'useState(${1:0})'),
  FlxSymbol('useRef', FlxKind.hook, 'Ref<T> useRef<T>(T initial)',
      'A mutable holder that does **not** rebuild. For values that survive '
      'rebuilds but should not trigger them.',
      snippet: r'useRef(${1:null})'),
  FlxSymbol('useMemoized', FlxKind.hook,
      'T useMemoized<T>(T Function() create, [List<Object?> keys])',
      'Caches a computation until `keys` change. Also the way to run '
      'setup exactly once per key during build, before the first frame.',
      snippet: r'useMemoized(() => ${1:value}, [${2:key}])'),
  FlxSymbol('useEffect', FlxKind.hook,
      'void useEffect(VoidCallback? Function() effect, [List<Object?> keys])',
      'A side effect with optional cleanup. Runs **after the frame**, never '
      'during build — so pushing a route from here is safe. Return a closure '
      'to clean up; it runs on key change and on dispose.',
      snippet: r'useEffect(() {\n  $1\n  return null;\n}, const [])'),
  FlxSymbol('useRebuild', FlxKind.hook, 'VoidCallback useRebuild()',
      'Returns a callback that schedules a rebuild. The escape hatch for '
      'bridging an external change source into the hooks engine.'),
  FlxSymbol('useListenable', FlxKind.hook,
      'T useListenable<T extends Listenable>(T listenable)',
      'Rebuilds whenever the Listenable notifies. Works with ValueNotifier, '
      'AnimationController, ScrollController and anything else Flutter '
      'exposes as a Listenable.',
      snippet: r'useListenable(${1:notifier})'),
  FlxSymbol('useTextEditingController', FlxKind.hook,
      'TextEditingController useTextEditingController({String text = \'\'})',
      'A controller tied to this composable\'s lifetime. Does **not** rebuild '
      'on typing — use `useTextField` when you need live validation.'),
  FlxSymbol('useTextField', FlxKind.hook,
      'TextEditingController useTextField({String text = \'\'})',
      'A controller that also rebuilds on every keystroke. This is what makes '
      'live validation work without lambdas: read `controller.text` straight '
      'from the build and the error updates as you type.',
      snippet: r'useTextField()'),
  FlxSymbol('useFocusNode', FlxKind.hook, 'FocusNode useFocusNode()',
      'A FocusNode disposed with the composable.'),
  FlxSymbol('useScrollController', FlxKind.hook,
      'ScrollController useScrollController()',
      'A ScrollController disposed with the composable.'),
  FlxSymbol('useFetch', FlxKind.hook,
      'AsyncValue<T> useFetch<T>(Future<T> Function() fetcher, {List<Object?> keys})',
      'Declarative async data. In a `val`, flxc generates the '
      '`AsyncValue.when` loading/error wrapping around the widget tree, so '
      'the name refers to the **resolved value** below.\n\n'
      'A later `val` cannot read that resolved value — hooks are positional, '
      'so it only exists inside the generated closure. Use `name\$.data`.',
      snippet: r'useFetch(${1:fetcher})'),
  FlxSymbol('useStream', FlxKind.hook,
      'AsyncValue<T> useStream<T>(Stream<T> stream, {T? initialData, List<Object?> keys})',
      'Subscribes to a stream and rebuilds on every event. The stream '
      'counterpart of `useFetch`, and what makes BLoC-style and '
      'Riverpod-style sources usable — their state arrives as a stream.\n\n'
      'In a `val` this generates the same `AsyncValue.when` wrapping as '
      '`useFetch`. Pass `initialData:` (a bloc\'s current state, say) to skip '
      'the loading frame. The subscription is cancelled on dispose.',
      snippet: r'useStream(${1:stream})'),
  FlxSymbol('useStreamValue', FlxKind.hook,
      'T useStreamValue<T>(T initial, Stream<T> stream, {List<Object?> keys})',
      'The latest value of a stream, without loading or error states. For '
      'sources that always have a current value, where `.when` wrapping is '
      'just noise.',
      snippet: r'useStreamValue(${1:initial}, ${2:stream})'),
  FlxSymbol('useInterval', FlxKind.hook,
      'void useInterval(VoidCallback callback, Duration delay)',
      'Runs a callback repeatedly. The timer is cancelled on dispose.'),
  FlxSymbol('useDebounced', FlxKind.hook,
      'T useDebounced<T>(T value, Duration delay)',
      'A value that only updates after `delay` with no further changes.'),
  FlxSymbol('useTheme', FlxKind.hook, 'ThemeData useTheme()',
      'The ambient ThemeData. Grab it in a `val` during build; using it inside\n'
      'a callback needs the captured value, not another hook call.'),
  FlxSymbol('useTextTheme', FlxKind.hook, 'TextTheme useTextTheme()',
      'The ambient TextTheme, for the Material type scale. `Styles` covers the\n'
      'shorthands the DSL understands.'),
  FlxSymbol('useColorScheme', FlxKind.hook, 'ColorScheme useColorScheme()',
      'The ambient ColorScheme — the seeded palette the app was themed with.'),
  FlxSymbol('useMediaQuery', FlxKind.hook, 'MediaQueryData useMediaQuery()',
      'The ambient MediaQueryData. Rebuilds on any change to it; prefer\n'
      '`useScreenSize` when only the size matters.'),
  FlxSymbol('useScreenSize', FlxKind.hook, 'Size useScreenSize()',
      'Screen size, without rebuilding on every MediaQuery change.'),
  FlxSymbol('useNavigator', FlxKind.hook, 'NavigatorState useNavigator()',
      'The Navigator. Capture it in a `val` during build and use it inside '
      'callbacks — `nav.to(Screen())` pushes an object, `nav.toPath("/x")` '
      'goes through the generated route table.'),
  FlxSymbol('useContext', FlxKind.hook, 'BuildContext useContext()',
      'The BuildContext of the composable currently building.'),
  FlxSymbol('useInject', FlxKind.hook, 'T useInject<T>()',
      'Resolves a dependency from the nearest `FlxScope`. Throws with '
      'registration instructions if nothing provides T.',
      snippet: r'useInject<${1:Service}>()'),
  FlxSymbol('useViewModel', FlxKind.hook, 'T useViewModel<T extends ViewModel>()',
      'Resolves a ViewModel and rebuilds this composable whenever it '
      'notifies.',
      snippet: r'useViewModel<${1:ViewModel}>()'),
];

const layoutWidgets = <FlxSymbol>[
  FlxSymbol('Column', FlxKind.layout, 'Column({double gap, MainAxisAlignment main, CrossAxisAlignment cross})',
      'Vertical layout. The block holds children, and `gap:` inserts spacing '
      'between them.',
      snippet: 'Column(gap: \${1:8}) {\n  \$0\n}'),
  FlxSymbol('Row', FlxKind.layout, 'Row({double gap, MainAxisAlignment main, CrossAxisAlignment cross})',
      'Horizontal layout. A `Field` or other unbounded-width child needs '
      '`expanded: true`.',
      snippet: 'Row(gap: \${1:8}) {\n  \$0\n}'),
  FlxSymbol('Stack', FlxKind.layout, 'Stack({AlignmentGeometry alignment})',
      'Children drawn on top of one another, positioned by `alignment:`. The\n'
      'first child is at the back.', snippet: 'Stack {\n  \$0\n}'),
  FlxSymbol('Wrap', FlxKind.layout, 'Wrap({double spacing, double runSpacing})',
      'Children laid out in a line that wraps onto the next when it runs out\n'
      'of room. Uses `spacing:` and `runSpacing:` rather than `gap:`.',
      snippet: 'Wrap(spacing: \${1:8}) {\n  \$0\n}'),
];

const containerWidgets = <FlxSymbol>[
  FlxSymbol('Screen', FlxKind.container,
      'Screen({String title, String subtitle, bool scrollable, IconData? actionIcon, VoidCallback? onAction, IconData? fabIcon, VoidCallback? onFab})',
      'A full screen: app bar, body and optional action button. The block '
      'becomes `children:`, which is how a widget tree reaches a named '
      'parameter.\n\n'
      'A `@page` rooted in a Screen is **not** wrapped in a second Scaffold. '
      'Leave `scrollable:` false when a child is a lazy list.',
      snippet: 'Screen(title: "\${1:Title}") {\n  \$0\n}'),
  FlxSymbol('Panel', FlxKind.container,
      'Panel({String title, double gap, EdgeInsets padding})',
      'A card grouping related children, with an optional title. The block\n'
      'becomes `children:`, the same as `Screen`.',
      snippet: 'Panel(title: "\${1:Title}") {\n  \$0\n}'),
];

const builderWidgets = <FlxSymbol>[
  FlxSymbol('LazyColumn', FlxKind.builder,
      'LazyColumn<T>({required List<T> items, double gap, VoidCallback? onEndReached, Widget? empty})',
      'A vertically scrolling list that builds only what is on screen. The '
      'block binds each element: `{ item in ... }` or `{ item, i in ... }`.\n\n'
      'Unlike `for`, which builds every child eagerly. `onEndReached` fires '
      'once per approach to the end, so it is safe to load a page from it.',
      snippet: 'LazyColumn(items: \${1:items}) { \${2:item} in\n  \$0\n}'),
  FlxSymbol('LazyRow', FlxKind.builder,
      'LazyRow<T>({required List<T> items, double gap, double? height})',
      'A horizontally scrolling lazy list. Inside a Column it needs `height:`.',
      snippet: 'LazyRow(items: \${1:items}, height: \${2:80}) { \${3:item} in\n  \$0\n}'),
  FlxSymbol('LazyGrid', FlxKind.builder,
      'LazyGrid<T>({required List<T> items, int columns, double gap, double aspectRatio})',
      'A lazy grid with a fixed number of columns.',
      snippet: 'LazyGrid(items: \${1:items}, columns: \${2:2}) { \${3:item} in\n  \$0\n}'),
];

const widgets = <FlxSymbol>[
  FlxSymbol('Text', FlxKind.widget, 'Text(String data, {TextStyle? style})',
      'Text. `style: .title` resolves against `Styles`.',
      snippet: r'Text("$1")'),
  FlxSymbol('Button', FlxKind.widget, 'Button(String label, VoidCallback onPressed)',
      'A filled button. The trailing block becomes the callback.',
      snippet: 'Button("\${1:Label}") {\n  \$0\n}'),
  FlxSymbol('Field', FlxKind.widget,
      'Field({required TextEditingController controller, String label, String? error, String? prefix, TextInputType? keyboard, bool obscure, int maxLines})',
      'A labelled text input with inline error display. Pair with '
      '`useTextField` so the error updates as you type. Inside a Row it needs '
      '`expanded: true` — a TextField has no intrinsic width.',
      snippet: 'Field(controller: \${1:controller}, label: "\${2:Label}")'),
  FlxSymbol('SearchField', FlxKind.widget,
      'SearchField(TextEditingController controller, ValueChanged<String> onChanged, {String hint})',
      'A search box with a clear button. The trailing block binds the new '
      'text: `{ text -> ... }`.',
      snippet: 'SearchField(\${1:controller}) { text ->\n  \$0\n}'),
  FlxSymbol('Picker', FlxKind.widget,
      'Picker<T>(T? value, List<T> options, ValueChanged<T> onChanged, {required String Function(T) labelOf, String label, String? error})',
      'A dropdown. The trailing block binds the selection.',
      snippet: 'Picker(\${1:value}, \${2:options}, labelOf: (o) => \${3:o.name}) { picked ->\n  \$0\n}'),
  FlxSymbol('Segmented', FlxKind.widget,
      'Segmented<T>(T value, List<T> options, ValueChanged<T> onChanged, {String Function(T)? labelOf})',
      'A single-choice segmented control, for a small fixed set of options —\n'
      'an enum, typically. Use `Picker` when the list is long.',
      snippet: 'Segmented(\${1:value}, \${2:Options.values}) { picked ->\n  \$0\n}'),
  FlxSymbol('DateField', FlxKind.widget,
      'DateField(DateTime value, ValueChanged<DateTime> onChanged, {String label})',
      'A read-only field that opens the platform date picker.',
      snippet: 'DateField(\${1:date}, label: "\${2:Date}") { picked ->\n  \$0\n}'),
  FlxSymbol('Toggle', FlxKind.widget,
      'Toggle(bool value, ValueChanged<bool> onChanged, {String label})',
      'A switch. With `label:` it becomes a full-width row; without one it is\n'
      'just the switch.',
      snippet: 'Toggle(\${1:value}, label: "\${2:Label}") { on ->\n  \$0\n}'),
  FlxSymbol('Tile', FlxKind.widget,
      'Tile({required String title, String subtitle, String trailing, Widget? leading, VoidCallback? onTap, bool dense})',
      'A tappable row: leading mark, title, subtitle, trailing value. The '
      'workhorse of list-heavy screens.',
      snippet: 'Tile(title: \${1:title})'),
  FlxSymbol('Stat', FlxKind.widget, 'Stat({required String value, required String label, Color? color})',
      'A headline figure with a caption, for dashboards.',
      snippet: 'Stat(value: \${1:value}, label: "\${2:Label}")'),
  FlxSymbol('Pill', FlxKind.widget, 'Pill(String label, {Color? color})',
      'A rounded label. Named Pill because Material already exports a Badge.'),
  FlxSymbol('Dot', FlxKind.widget, 'Dot(Color color, {double size})',
      'A small coloured dot, for marking a category in a list.'),
  FlxSymbol('ProgressBar', FlxKind.widget,
      'ProgressBar(double fraction, {Color? color, double height, bool isOver})',
      'A progress bar. The fraction is clamped, so an over-budget value fills '
      'rather than overflowing.',
      snippet: r'ProgressBar(${1:fraction})'),
  FlxSymbol('EmptyState', FlxKind.widget,
      'EmptyState({required String title, String subtitle, IconData icon, Widget? action})',
      'Shown when a list has nothing in it — a blank screen reads as a bug.',
      snippet: 'EmptyState(title: "\${1:Nothing here}")'),
  FlxSymbol('Section', FlxKind.widget,
      'Section({required String title, required Widget child, Widget? action})',
      'A titled section with an optional trailing action.'),
  FlxSymbol('Avatar', FlxKind.widget, 'Avatar(String? url, {double size})',
      'A circular avatar, falling back to a person icon.'),
  FlxSymbol('Icon', FlxKind.widget, 'Icon(IconData icon, {double? size, Color? color})',
      'A Material icon. `icon: .add` resolves against `Icons`.'),
  FlxSymbol('LayoutBuilder', FlxKind.widget,
      'LayoutBuilder({required Widget Function(BuildContext, BoxConstraints) builder})',
      'Builds against the incoming constraints. The trailing block binds them '
      'and produces the widget:\n\n'
      '```\nLayoutBuilder { context, box =>\n  Text("\${box.maxWidth}")\n}\n```',
      snippet: 'LayoutBuilder { context, box =>\n  \$0\n}'),
  FlxSymbol('StreamBuilder', FlxKind.widget,
      'StreamBuilder<T>({Stream<T>? stream, T? initialData, required Widget Function(BuildContext, AsyncSnapshot<T>) builder})',
      'Rebuilds on each stream event. Usually `useStream` in a `val` reads '
      'better; reach for this when you need the snapshot itself.',
      snippet: 'StreamBuilder(stream: \${1:stream}) { context, snapshot =>\n  \$0\n}'),
  FlxSymbol('FutureBuilder', FlxKind.widget,
      'FutureBuilder<T>({Future<T>? future, T? initialData, required Widget Function(BuildContext, AsyncSnapshot<T>) builder})',
      'Rebuilds as a future resolves. `useFetch` in a `val` is the flx way; '
      'this is here for interop with code that already hands you a Future.',
      snippet: 'FutureBuilder(future: \${1:future}) { context, snapshot =>\n  \$0\n}'),
  FlxSymbol('ValueListenableBuilder', FlxKind.widget,
      'ValueListenableBuilder<T>({required ValueListenable<T> valueListenable, required Widget Function(BuildContext, T, Widget?) builder})',
      'Rebuilds when a ValueListenable changes. `useListenable` usually reads '
      'better, since it needs no extra nesting.',
      snippet: 'ValueListenableBuilder(valueListenable: \${1:notifier}) { context, value, child =>\n  \$0\n}'),
  FlxSymbol('AnimatedBuilder', FlxKind.widget,
      'AnimatedBuilder({required Listenable animation, required Widget Function(BuildContext, Widget?) builder})',
      'Rebuilds on every tick of an animation.',
      snippet: 'AnimatedBuilder(animation: \${1:controller}) { context, child =>\n  \$0\n}'),
  FlxSymbol('Builder', FlxKind.widget,
      'Builder({required Widget Function(BuildContext) builder})',
      'Introduces a new BuildContext below this point — the fix for "no '
      'Scaffold above this context".',
      snippet: 'Builder { context =>\n  \$0\n}'),
  FlxSymbol('Scaffold', FlxKind.widget,
      'Scaffold({PreferredSizeWidget? appBar, Widget? body, Widget? floatingActionButton, Widget? drawer})',
      'Flutter\'s own page scaffold. `Screen` wraps it with an app bar and '
      'action button already wired; use this when you need the full surface.',
      snippet: 'Scaffold(\n  appBar: AppBar(title: Text("\${1:Title}")),\n  body: \$0,\n)'),
  FlxSymbol('AppBar', FlxKind.widget,
      'AppBar({Widget? title, List<Widget>? actions, Widget? leading})',
      'The top bar of a Scaffold.',
      snippet: 'AppBar(title: Text("\${1:Title}"))'),
  FlxSymbol('SizedBox', FlxKind.widget, 'SizedBox({double? width, double? height})',
      'Fixed-size box, usually for spacing. Prefer `gap:` on a layout.'),
  FlxSymbol('Spacer', FlxKind.widget, 'Spacer({int flex})',
      'Takes up remaining space inside a Row or Column.'),
  FlxSymbol('Divider', FlxKind.widget, 'Divider({double? height, double? thickness})',
      'A horizontal rule. Inside a `LazyColumn` prefer `gap:`, which does not\n'
      'add a widget per row.'),
];

const keywords = <FlxSymbol>[
  FlxSymbol('composable', FlxKind.keyword, 'composable Name(params) { ... }',
      'Declares a composable. A file may hold several — a screen plus the '
      'components it is built from. Must start with a capital letter.',
      snippet: 'composable \${1:Name} {\n  \$0\n}'),
  FlxSymbol('val', FlxKind.keyword, 'val name = expression',
      'A build-time binding. All `val`s come before the widget tree.',
      snippet: r'val ${1:name} = ${2:expression}'),
  FlxSymbol('import', FlxKind.keyword, 'import "path.dart"',
      'A Dart import, passed through to the generated file. Imports come '
      'first, before any annotation or composable.',
      snippet: r'import "${1:../data/thing.dart}"'),
  FlxSymbol('page', FlxKind.keyword, '@page("/route")',
      'Marks a composable as a screen: it is wrapped in a Scaffold (unless '
      'rooted in a `Screen`) and registered in the generated route table. '
      '`:param` segments must match a composable parameter of type String.',
      snippet: r'@page("/${1:route}")'),
  FlxSymbol('if', FlxKind.keyword, 'if (condition) { ... } else { ... }',
      'Conditional children. Compiles to Dart collection-if, so a branch may '
      'hold several widgets. Cannot be the root of a composable.',
      snippet: 'if (\${1:condition}) {\n  \$0\n}'),
  FlxSymbol('for', FlxKind.keyword, 'for (item in items) { ... }',
      'Repeated children, compiled to collection-for. Builds every child '
      'eagerly — use `LazyColumn` for long lists.',
      snippet: 'for (\${1:item} in \${2:items}) {\n  \$0\n}'),
];

/// Named arguments accepted by the layout widgets.
const layoutArguments = <String, String>{
  'gap': 'Spacing inserted between children.',
  'main': 'MainAxisAlignment — `.center`, `.spaceBetween`, `.start`, `.end`.',
  'cross': 'CrossAxisAlignment — `.start`, `.center`, `.stretch`.',
  'size': 'MainAxisSize — `.min` or `.max`.',
  'alignment': 'Alignment, on Stack.',
  'spacing': 'Spacing between children, on Wrap.',
  'runSpacing': 'Spacing between lines, on Wrap.',
};

/// Arguments lifted out of the call into a trailing modifier chain.
const modifierArguments = <String, String>{
  'padding': 'Wraps in Padding. On a layout widget only — container and '
      'builder widgets declare a real `padding` parameter.',
  'paddingSymmetric': 'Wraps in symmetric Padding.',
  'background': 'Wraps in a coloured DecoratedBox.',
  'rounded': 'Clips to a rounded rectangle.',
  'opacity': 'Wraps in Opacity.',
  'center': 'Wraps in Center. Flag: `center: true`.',
  'safeArea': 'Wraps in SafeArea. Flag.',
  'scrollable': 'Wraps in a scroll view. Flag, layout widgets only.',
  'expanded': 'Wraps in Expanded — what a lazy list inside a Screen needs.',
  'card': 'Wraps in an elevated, clipped Material.',
};

/// Argument names offered per widget, beyond the modifiers.
const widgetArguments = <String, List<String>>{
  'Screen': [
    'title', 'subtitle', 'scrollable', 'padding', 'gap', 'showBack',
    'actionIcon', 'onAction', 'actionTooltip', 'fabIcon', 'onFab', 'fabLabel',
    'cross',
  ],
  'Panel': ['title', 'padding', 'gap', 'cross'],
  'LazyColumn': [
    'items', 'gap', 'padding', 'empty', 'controller', 'onEndReached',
    'shrinkWrap', 'physics',
  ],
  'LazyRow': ['items', 'gap', 'padding', 'empty', 'controller', 'height'],
  'LazyGrid': [
    'items', 'columns', 'gap', 'aspectRatio', 'padding', 'empty', 'controller',
  ],
  'Text': ['style', 'textAlign', 'maxLines', 'overflow'],
  'Field': [
    'controller', 'label', 'hint', 'error', 'keyboard', 'prefix', 'suffix',
    'maxLines', 'autofocus', 'enabled', 'obscure', 'focusNode', 'onSubmitted',
  ],
  'SearchField': ['hint'],
  'Picker': ['labelOf', 'label', 'error'],
  'Segmented': ['labelOf'],
  'DateField': ['label', 'firstDate', 'lastDate'],
  'Toggle': ['label'],
  'Tile': [
    'title', 'subtitle', 'trailing', 'trailingColor', 'leading', 'onTap',
    'dense',
  ],
  'Stat': ['value', 'label', 'color'],
  'Pill': ['color'],
  'Dot': ['size'],
  'ProgressBar': ['color', 'overColor', 'height', 'isOver'],
  'EmptyState': ['title', 'subtitle', 'icon', 'action'],
  'Section': ['title', 'child', 'action'],
  'Avatar': ['size'],
  'Icon': ['size', 'color'],
  'LayoutBuilder': ['builder'],
  'StreamBuilder': ['stream', 'initialData', 'builder'],
  'FutureBuilder': ['future', 'initialData', 'builder'],
  'ValueListenableBuilder': ['valueListenable', 'builder', 'child'],
  'AnimatedBuilder': ['animation', 'builder', 'child'],
  'Builder': ['builder'],
  'Scaffold': [
    'appBar', 'body', 'floatingActionButton', 'drawer', 'bottomNavigationBar',
    'backgroundColor',
  ],
  'AppBar': ['title', 'actions', 'leading', 'centerTitle', 'backgroundColor'],
  'SizedBox': ['width', 'height'],
  'Spacer': ['flex'],
  'Divider': ['height', 'thickness', 'color'],
};

/// Argument name → the type its `.shorthand` resolves against, and the
/// members worth offering.
const shorthandValues = <String, (String, List<String>)>{
  'style': ('Styles', ['title', 'subtitle', 'body', 'caption']),
  'main': (
    'MainAxisAlignment',
    ['start', 'end', 'center', 'spaceBetween', 'spaceAround', 'spaceEvenly'],
  ),
  'cross': (
    'CrossAxisAlignment',
    ['start', 'end', 'center', 'stretch', 'baseline'],
  ),
  'size': ('MainAxisSize', ['min', 'max']),
  'textAlign': ('TextAlign', ['left', 'right', 'center', 'justify', 'start', 'end']),
  'overflow': ('TextOverflow', ['clip', 'fade', 'ellipsis', 'visible']),
  'fit': ('BoxFit', ['fill', 'contain', 'cover', 'fitWidth', 'fitHeight', 'none', 'scaleDown']),
  'axis': ('Axis', ['horizontal', 'vertical']),
  'alignment': (
    'Alignment',
    ['topLeft', 'topCenter', 'topRight', 'centerLeft', 'center', 'centerRight',
     'bottomLeft', 'bottomCenter', 'bottomRight'],
  ),
  'keyboard': (
    'TextInputType',
    ['text', 'number', 'phone', 'emailAddress', 'multiline', 'url'],
  ),
};

/// A few common Material icons, for `*Icon:` arguments.
const commonIcons = <String>[
  'add', 'edit', 'delete', 'close', 'check', 'search', 'settings', 'share',
  'refresh', 'arrow_back', 'arrow_forward', 'more_vert', 'filter_list',
  'calendar_today', 'person', 'home', 'star', 'favorite', 'download', 'upload',
  'visibility', 'visibility_off', 'info_outline', 'warning_amber',
];

/// Everything that can appear where a widget is expected.
List<FlxSymbol> get allWidgets => [
      ...layoutWidgets,
      ...containerWidgets,
      ...builderWidgets,
      ...widgets,
    ];

/// Every documented symbol, for hover lookup.
final Map<String, FlxSymbol> symbolsByName = {
  for (final symbol in [...hooks, ...allWidgets, ...keywords]) symbol.name: symbol,
};
