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

There is no `main.dart` and nothing to run.
