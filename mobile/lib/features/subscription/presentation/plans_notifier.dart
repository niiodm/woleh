import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/plans_dto.dart';
import '../data/plans_repository.dart';

part 'plans_notifier.g.dart';

@Riverpod(keepAlive: true)
class PlansNotifier extends _$PlansNotifier {
  @override
  Future<List<PlanDto>> build() async {
    return ref.read(plansRepositoryProvider).getPlans();
  }
}
