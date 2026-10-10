import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:namer_app/ui/responsive.dart';

class PingPongGame extends StatefulWidget {
  const PingPongGame({Key? key}) : super(key: key);

  @override
  State<PingPongGame> createState() => _PingPongGameState();
}

class _PingPongGameState extends State<PingPongGame> {
  double ballX = 0.0;
  double ballY = 0.0;
  double ballSpeedX = 0.02;
  double ballSpeedY = 0.01;
  double paddleX = 0.0;
  int score = 0;
  Timer? _gameTimer;

  @override
  void initState() {
    super.initState();
    _startGame();
  }

  void _startGame() {
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) return;
      setState(() {
        // Move ball
        ballX += ballSpeedX;
        ballY += ballSpeedY;

        // Ball collision with walls
        if (ballX >= 1.0 || ballX <= -1.0) {
          ballSpeedX = -ballSpeedX;
        }
        if (ballY <= -1.0) {
          ballSpeedY = -ballSpeedY;
        }

        // Ball collision with paddle
        if (ballY >= 0.9 &&
            ballY <= 1.0 &&
            ballX >= paddleX - 0.2 &&
            ballX <= paddleX + 0.2) {
          ballSpeedY = -ballSpeedY.abs();
          score++;
          // Speed up slightly
          if (ballSpeedX > 0) {
            ballSpeedX = (ballSpeedX * 1.05).clamp(0.01, 0.04);
          } else {
            ballSpeedX = (ballSpeedX * 1.05).clamp(-0.04, -0.01);
          }
          ballSpeedY = (ballSpeedY * 1.05).clamp(-0.04, -0.01);
        }

        // Reset if ball falls off bottom
        if (ballY > 1.0) {
          ballX = 0.0;
          ballY = 0.0;
          ballSpeedX = 0.02;
          ballSpeedY = 0.01;
          score = 0;
        }
      });
    });
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fit narrow and short screens: never wider than the space
            // allows, never taller than half the screen.
            final double courtWidth =
                math.max(120.0, math.min(300.0, constraints.maxWidth - 48));
            final double courtHeight =
                math.max(160.0, math.min(400.0, screenHeight * 0.5));
            return Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: AppDecor.card,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Text(
                              'Coach is working out your numbers…',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Score: $score',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: GestureDetector(
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              // Alignment runs -1..1 across the court, so a
                              // drag of half the width moves one unit.
                              paddleX += details.delta.dx / (courtWidth / 2);
                              paddleX = paddleX.clamp(-0.8, 0.8);
                            });
                          },
                          child: Container(
                            width: courtWidth,
                            height: courtHeight,
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Stack(
                              children: [
                                // Ball
                                Align(
                                  alignment: Alignment(ballX, ballY),
                                  child: Container(
                                    width: 15,
                                    height: 15,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                // Paddle
                                Align(
                                  alignment: Alignment(paddleX, 0.95),
                                  child: Container(
                                    width: courtWidth / 5,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Drag to move the paddle',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
