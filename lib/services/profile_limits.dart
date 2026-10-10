/// The ranges we accept for "About you", shared by Get started, Goals and
/// profile and the weight log so they can never disagree. Values are
/// always metric (cm, kg); the units service converts for display.
class ProfileLimits {
  ProfileLimits._();

  static const int minAge = 13;
  static const int maxAge = 120;

  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;

  static const double minWeightKg = 30;
  static const double maxWeightKg = 350;

  static bool ageOk(num? age) =>
      age != null && age.isFinite && age >= minAge && age <= maxAge;

  static bool heightOk(num? cm) =>
      cm != null && cm.isFinite && cm >= minHeightCm && cm <= maxHeightCm;

  static bool weightOk(num? kg) =>
      kg != null && kg.isFinite && kg >= minWeightKg && kg <= maxWeightKg;

  static String get ageRangeMessage =>
      'Enter an age between $minAge and $maxAge';
}
