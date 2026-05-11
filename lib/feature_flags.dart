/// Central toggles for unfinished or paused product areas.
abstract final class FeatureFlags {
  FeatureFlags._();

  /// Buy fruits list / procurement tab (admin + fruit-buyer role).
  static const bool showFruitBuyUi = false;
}
