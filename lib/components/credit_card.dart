import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:namer_app/components/calorie_currency_icon.dart';

class CreditCard extends StatefulWidget {
  final int? initialCalories; // Add initial calories parameter

  const CreditCard({
    Key? key,
    this.initialCalories,
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
    // Set initial calories if provided
    if (widget.initialCalories != null) {
      calories = widget.initialCalories!;
      isLoading = false;
    } else {
      // Fetch calories from Firebase if not provided
      _fetchUserData();
    }
  }

  @override
  void didUpdateWidget(CreditCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update calories if the initialCalories parameter changes
    if (widget.initialCalories != oldWidget.initialCalories &&
        widget.initialCalories != null) {
      setState(() {
        calories = widget.initialCalories!;
      });
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
          calories = userData['calories'] ?? 0;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching user data: $e');
      setState(() {
        isLoading = false;
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
        height: 155,
        width: 350,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF6366F1),
              const Color(0xFF4F46E5),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            const BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              spreadRadius: 1,
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),

              // Calorie Currency Icon and Calories
              Positioned(
                top: 8,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        CalorieCurrencyIcon(),
                        const SizedBox(width: 6),
                        Text(
                          calories.toString(),
                          style: GoogleFonts.robotoMono(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Balance',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Credit Card Chip
              Positioned(
                top: 40,
                left: 16,
                child: Container(
                  width: 34,
                  height: 26,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.shade300,
                        Colors.amber.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),

              // Valid Thru (bottom left)
              Positioned(
                bottom: 16,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VALID THRU',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      today,
                      style: GoogleFonts.robotoMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Username (bottom right)
              Positioned(
                bottom: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    _getTruncatedName(
                        FirebaseAuth.instance.currentUser!.email!),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
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
