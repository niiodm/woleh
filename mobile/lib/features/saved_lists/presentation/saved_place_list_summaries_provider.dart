import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/saved_place_list_dto.dart';
import '../data/saved_place_list_repository.dart';

part 'saved_place_list_summaries_provider.g.dart';

@riverpod
Future<List<SavedPlaceListSummaryDto>> savedPlaceListSummaries(Ref ref) {
  return ref.watch(savedPlaceListRepositoryProvider).listSummaries();
}
