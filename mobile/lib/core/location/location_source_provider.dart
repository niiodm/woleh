import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'geolocator_location_source.dart';
import 'location_source.dart';

part 'location_source_provider.g.dart';

@Riverpod(keepAlive: true)
LocationSource locationSource(Ref ref) => GeolocatorLocationSource();
