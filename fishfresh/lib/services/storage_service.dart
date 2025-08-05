import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  Future<void> setOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
  }

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_seen') ?? false;
  }
}
