import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const _kOnboardingSeenKey = 'onboarding_seen_v1'; // version your key

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // ✅ default to FALSE (not seen)
    return prefs.getBool(_kOnboardingSeenKey) ?? false;
  }

  Future<void> setSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeenKey, true);
  }

  // Optional: to reset for debugging
  Future<void> clearOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kOnboardingSeenKey);
  }
}
