<p align="center">
  <img src="../../assets/flx-icon-128.png" width="88" alt="flx">
</p>

# interop

Not an app. A compile target that proves flx composes with the ecosystem
instead of replacing it.

`lib/pages/interop.flx` is one screen using **BLoC, Provider and GetX at the
same time**, alongside flx's own hooks. It exercises every shape a third-party
widget API takes:

| Shape | Example here |
| --- | --- |
| Named `builder:` with parameters | `BlocBuilder`, `Consumer` |
| Positional zero-argument builder | GetX's `Obx` |
| A stream as the source of state | `useStream(cubit.stream, initialData: cubit.state)` |
| Plain function call in a `val` | `Provider.of<Settings>(useContext())`, `Get.find<GetxCounter>()` |

`make ci` analyzes it. If a codegen change makes any of these unreachable
again, this fails — which is the point. The claim "flx has no limitations" is
only worth making if something checks it.

## UI packages

`lib/pages/ui_packages.flx` does the same for widget libraries, again chosen
for API shape rather than popularity:

| Package | The shape it exercises |
| --- | --- |
| `cached_network_image` | Two builder callbacks on one widget (`placeholder:`, `errorWidget:`) |
| `shimmer` | Named constructor with a widget-valued `child:` |
| `flutter_svg` | Named constructor (`SvgPicture.asset`) |
| `flutter_staggered_grid_view` | Named constructor plus an `itemBuilder:` |
| `flutter_slidable` | Widget-valued arguments nested inside a list |
| `fl_chart` | Deeply nested configuration objects |
| `google_fonts` | A package call in an ordinary argument |

There is no `main.dart` and nothing to run.
