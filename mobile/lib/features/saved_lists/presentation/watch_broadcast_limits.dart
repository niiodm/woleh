import '../../me/data/me_dto.dart';

/// Max place names allowed in a saved list template (same rule as server).
int savedListMaxPlaceNames(MeResponse me) {
  if (me.permissions.contains('woleh.place.broadcast')) {
    return me.limits.placeBroadcastMax;
  }
  return me.limits.placeWatchMax;
}
