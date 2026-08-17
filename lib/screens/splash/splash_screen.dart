import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.black,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Image(
            image: AssetImage('assets/branding/map_transparent_dark.png'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
