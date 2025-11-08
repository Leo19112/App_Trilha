import 'package:flutter/foundation.dart';

class SelectedTrailId extends ValueNotifier<String?> {
  SelectedTrailId() : super(null);
  void select(String id) => value = id;
  void clear() => value = null;
}

final selectedTrailId = SelectedTrailId();
