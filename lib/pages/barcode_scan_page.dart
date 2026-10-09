import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:namer_app/ui/responsive.dart';

/// "Contactless": point the camera at a barcode. Pops with the barcode
/// digits. The number can also be typed in (handy on a laptop without a
/// camera, or a crumpled wrapper).
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  final TextEditingController _manual = TextEditingController();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Release the camera while the app is in the background and take it
  /// back on return (otherwise it can come back black on iOS).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.stop().catchError((_) {});
    } else if (state == AppLifecycleState.resumed && !_done) {
      _controller.start().catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String code) {
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (_done) return;
    if (digits.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Barcodes are usually 8 or 13 digits long.')),
      );
      return;
    }
    _done = true;
    Navigator.pop(context, digits);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty) {
        _finish(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan barcode'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                IgnorePointer(
                  child: Container(
                    width: 260,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 24,
                  child: Text(
                    'Line the barcode up in the box',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manual,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Or type the barcode number',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _finish,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark),
                    onPressed: () => _finish(_manual.text),
                    child: const Text('Look up'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
