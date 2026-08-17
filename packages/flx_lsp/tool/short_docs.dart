import 'package:flx_lsp/src/catalog.dart';

/// Lists catalog entries whose documentation is too thin to be worth reading.
void main() {
  for (final symbol in [...hooks, ...allWidgets, ...keywords]) {
    if (symbol.documentation.length < 40) {
      print('${symbol.documentation.length}  ${symbol.name}: '
          '${symbol.documentation}');
    }
  }
}
