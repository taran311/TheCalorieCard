import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:namer_app/components/calorie_currency_icon.dart';
import 'package:namer_app/components/performance_gauge.dart';
import 'package:namer_app/components/running_man_widget.dart';
import 'package:namer_app/components/glass_of_water.dart';

Future<void> _updateWater(int water) async {
  QuerySnapshot userDataSnapshot = await FirebaseFirestore.instance
      .collection('user_data')
      .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .get();

  final docRef = FirebaseFirestore.instance
      .collection('user_data')
      .doc(userDataSnapshot.docs.first.id);

  await docRef.update({
    'water': water,
  });
}

Future<void> _updateSteps(int steps) async {
  QuerySnapshot userDataSnapshot = await FirebaseFirestore.instance
      .collection('user_data')
      .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .get();

  final docRef = FirebaseFirestore.instance
      .collection('user_data')
      .doc(userDataSnapshot.docs.first.id);

  await docRef.update({
    'steps': steps,
  });
}

class CreditCard extends StatefulWidget {
  final bool showWater;
  final bool showSteps;
  final bool showPerformanceGauge;
  final void Function(double)? onWaterUpdated; // Updated to accept a double

  const CreditCard({
    Key? key,
    this.showWater = false,
    this.showSteps = false,
    this.showPerformanceGauge = false,
    this.onWaterUpdated,
  }) : super(key: key);

  @override
  State<CreditCard> createState() => _CreditCardWidgetState();
}

class _CreditCardWidgetState extends State<CreditCard> {
  double waterIntake = 0.0; // Initial hydration in liters
  int steps = 0; // Initial steps
  int calories = 0; // Initial calorie balance
  bool isLoading = true; // Loading state

  @override
  void initState() {
    super.initState();
    if (widget.showWater || widget.showSteps || widget.showPerformanceGauge) {
      _fetchUserData();
    } else {
      isLoading = false;
    }
  }

  Future<void> _fetchUserData() async {
    try {
      QuerySnapshot userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (userDataSnapshot.docs.isNotEmpty) {
        final userData =
            userDataSnapshot.docs.first.data() as Map<String, dynamic>;
        setState(() {
          waterIntake = (userData['water'] ?? 0).toDouble();
          steps = userData['steps'] ?? 0;
          calories = userData['calories'] ?? 0;
          isLoading = false; // Stop loading
        });
      }
    } catch (e) {
      print('Error fetching user data: $e');
      setState(() {
        isLoading = false; // Stop loading even on error
      });
    }
  }

  // Calculate the performance gauge value
  double calculatePerformanceGaugeValue() {
    final int calorieBalance = calories;

    // Hydration score: normalize to 0-100
    double hydrationScore = (waterIntake / 5.0) * 100;

    // Steps score: normalize to 0-100
    double stepsScore = (steps / 10000) * 100;

    // Calorie score logic
    double calorieScore;
    if (calorieBalance == 0) {
      calorieScore = 90; // Start strongly in green
    } else if (calorieBalance.abs() <= 500) {
      calorieScore =
          90 - (calorieBalance.abs() / 500 * 20); // Scale gently down
    } else {
      calorieScore = max(
          60 - ((calorieBalance.abs() - 500) / 500 * 30), 0); // Drop further
    }

    // Combine scores with adjusted weights:
    double overallScore =
        (calorieScore * 0.7) + (hydrationScore * 0.15) + (stepsScore * 0.15);

    return overallScore.clamp(0, 100);
  }

  Future<void> _updateWaterIntake(double value) async {
    setState(() {
      waterIntake = value;
    });

    await _updateWater(value.toInt());

    // Notify the HomePage to trigger the water animation
    if (widget.onWaterUpdated != null) {
      widget.onWaterUpdated!(waterIntake);
    }
  }

  Future<void> _updateStepsInput(int value) async {
    setState(() {
      steps = value;
    });

    await _updateSteps(value);
  }

  @override
  Widget build(BuildContext context) {
    final String today =
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return GestureDetector(
      child: Container(
        height: 200,
        width: 350,
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Stack(
            children: [
              // Brand Name
              Positioned(
                top: 8,
                left: 16,
                child: Text(
                  'TheCalorieCard',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              // Calorie Currency Icon and Calories
              Positioned(
                top: 8,
                right: 16,
                child: Row(
                  children: [
                    CalorieCurrencyIcon(),
                    const SizedBox(width: 6),
                    Text(
                      calories.toString(),
                      style: GoogleFonts.robotoMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Credit Card Chip
              Positioned(
                top: 48,
                left: 16,
                child: Container(
                  width: 40,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // Glass of Water and Running Man Widgets
              Positioned(
                top: 56,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        // Glass of Water Widget
                        if (widget.showWater)
                          SizedBox(
                            height: 50,
                            child: GlassOfWaterWidget(
                              onWaterLevelChanged: _updateWaterIntake,
                              initialValue: waterIntake,
                            ),
                          ),
                        if (widget.showWater && widget.showSteps)
                          const SizedBox(width: 10),
                        // Running Man Widget
                        if (widget.showSteps)
                          SizedBox(
                            height: 50,
                            child: RunningManWidget(
                              onStepsChanged: _updateStepsInput,
                              initialSteps: steps,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20), // Space before the gauge
                    if (widget.showPerformanceGauge)
                      PerformanceGauge(
                        value: calculatePerformanceGaugeValue(),
                      ),
                  ],
                ),
              ),

              // Valid Thru and Username Section
              Positioned(
                bottom: 16,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VALID',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            Text(
                              'THRU',
                              style: TextStyle(
                                fontSize: 8,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Text(
                          today,
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _getTruncatedName(
                          FirebaseAuth.instance.currentUser!.email!),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Limit the name to 25 characters with "..." if truncated
String _getTruncatedName(String name) {
  if (name.length > 25) {
    return '${name.substring(0, 22)}...';
  }
  return name;
}
