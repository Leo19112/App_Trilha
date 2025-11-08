import 'package:flutter/material.dart';

/// Controlador simples de navegação por abas.
/// Mantém o índice atual e notifica ouvintes quando mudar.
class NavBloc extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  void setIndex(int index) {
    if (index == _currentIndex) return;
    _currentIndex = index;
    notifyListeners();
  }
}
