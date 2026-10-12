import 'dart:async';

import 'package:digitalkhata/authentication/loginscreen.dart';
import 'package:digitalkhata/db/dbprovider.dart';
import 'package:digitalkhata/screens/mainscreen.dart';
import 'package:digitalkhata/screens/onboarding_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Splashservises {
  static const Duration _minimumSplash = Duration(milliseconds: 1000);

  /// Shows the splash just long enough for the local database to load, so the
  /// next screen opens fully ready (no second loading screen, no white flash).
  Future<void> login(BuildContext context) async {
    final started = DateTime.now();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null && context.mounted) {
      // Dbprovider handles its own load errors; this never throws.
      await context.read<Dbprovider>().openForUser(user.uid);
    }

    final preferences = await SharedPreferences.getInstance();
    final onboardingComplete =
        preferences.getBool(OnboardingScreen.completeKey) ?? false;

    final remaining = _minimumSplash - DateTime.now().difference(started);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (!context.mounted) return;

    final Widget destination;
    if (!onboardingComplete) {
      destination = const OnboardingScreen();
    } else {
      destination = user == null ? const AuthScreen() : const Mainscreen();
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => destination,
        transitionDuration: const Duration(milliseconds: 420),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}
