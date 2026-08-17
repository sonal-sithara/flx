import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);
  void increment() => emit(state + 1);
}

class Settings extends ChangeNotifier {
  String name = 'Ada';
  void rename(String value) {
    name = value;
    notifyListeners();
  }
}

class GetxCounter extends GetxController {
  final count = 0.obs;
  void increment() => count.value++;
}
