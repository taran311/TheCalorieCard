import 'dart:async';
import 'package:flutter/material.dart';

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
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'AI is calculating...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Play Ping Pong! Score: $score',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    paddleX += details.delta.dx / 150;
                    paddleX = paddleX.clamp(-0.8, 0.8);
                  });
                },
                child: Container(
                  width: 300,
                  height: 400,
                  decoration: BoxDecoration(
                    color: Colors.black87,
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
                          width: 60,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Swipe to move paddle',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
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
