import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'phase_label.g.dart';

/// Placeholder provider to verify Riverpod codegen (Phase 0 layout).
@riverpod
String phaseLabel(Ref ref) => 'Phase 0';
