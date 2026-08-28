import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// What it costs to take a card to one particular level.
class UpgradeStep {
  const UpgradeStep({
    required this.level,
    required this.copies,
    required this.coins,
  });

  /// The level this step *reaches*.
  final int level;
  final int copies;
  final int coins;

  factory UpgradeStep.fromJson(Map<String, dynamic> json) => UpgradeStep(
    level: (json['level'] as num).toInt(),
    copies: (json['copies'] as num).toInt(),
    coins: (json['coins'] as num).toInt(),
  );
}

/// The card-level curve, from `assets/data/upgrade_costs.json`.
class UpgradeCosts {
  const UpgradeCosts(this.steps);

  final List<UpgradeStep> steps;

  int get maxLevel =>
      steps.isEmpty ? 1 : steps.map((s) => s.level).reduce((a, b) => a > b ? a : b);

  /// What it costs to go from [level] to [level] + 1, or null at the cap.
  UpgradeStep? stepFrom(int level) {
    for (final step in steps) {
      if (step.level == level + 1) return step;
    }
    return null;
  }

  bool isMaxed(int level) => stepFrom(level) == null;

  /// Whether a card at [level] can be upgraded right now.
  bool canAfford({
    required int level,
    required int copies,
    required int coins,
  }) {
    final step = stepFrom(level);
    if (step == null) return false;
    return copies >= step.copies && coins >= step.coins;
  }

  static UpgradeCosts fromJson(Map<String, dynamic> json) => UpgradeCosts([
    for (final s in json['levels'] as List<dynamic>)
      UpgradeStep.fromJson(s as Map<String, dynamic>),
  ]);

  static Future<UpgradeCosts> load() async {
    final raw = await rootBundle.loadString('assets/data/upgrade_costs.json');
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
