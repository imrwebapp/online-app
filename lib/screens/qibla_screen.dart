import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  bool _granted = false;
  Position? _position;
  double? _deviceHeading;
  double? _bearingToKaaba;

  bool _hasCompass = false;
  double _fallbackTilt = 0;

  static const double kaabaLat = 21.4225;
  static const double kaabaLng = 39.8262;

  double compassHorizontalOffset = 0.0;
  double compassVerticalOffset = 30.0;
  double compassSize = 280.0;

  @override
  void initState() {
    super.initState();
    _detectCompassSensor();
    _listenCompass();
    _listenAccelerometer();
    _requestPermissionAndInit();
  }

  void _detectCompassSensor() async {
    try {
      final firstReading = await FlutterCompass.events?.first;
      if (!mounted) return;
      setState(() {
        _hasCompass = firstReading?.heading != null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasCompass = false);
    }
  }

  void _listenCompass() {
    FlutterCompass.events?.listen((event) {
      if (!_hasCompass || !mounted) return;
      setState(() {
        _deviceHeading = event.heading;
      });
    });
  }

  void _listenAccelerometer() {
    accelerometerEventStream().listen((AccelerometerEvent e) {
      if (_hasCompass || !mounted) return;
      final tilt = math.atan2(e.x, e.y);
      setState(() {
        _fallbackTilt = tilt * 180 / math.pi;
      });
    });
  }

  Future<void> _requestPermissionAndInit() async {
    try {
      // Step 1: Check if location services are on
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location services are disabled. Please enable them in your device settings."),
          ),
        );
        setState(() => _granted = false);
        return;
      }

      // Step 2: Check/request permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        // ✅ Apple-compliant: do NOT auto-open Settings here.
        // Just inform the user gracefully and let them choose.
        if (!mounted) return;
        setState(() => _granted = false);
        _showPermissionDeniedDialog();
        return;
      }

      if (permission == LocationPermission.denied) {
        // User dismissed/denied — accept gracefully
        if (!mounted) return;
        setState(() => _granted = false);
        return;
      }

      // Step 3: Permission granted — get position
      if (!mounted) return;
      setState(() => _granted = true);

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      if (!mounted) return;
      setState(() {
        _position = pos;
        _bearingToKaaba = _calculateBearing(
          pos.latitude,
          pos.longitude,
          kaabaLat,
          kaabaLng,
        );
      });
    } catch (e) {
      debugPrint("Location error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not retrieve location. Please try again.")),
      );
    }
  }

  /// ✅ Apple-compliant Settings dialog.
  /// Only shown AFTER denial, as an informational prompt — not an automatic redirect.
  /// Always includes a "Cancel" option so the user is never forced to Settings.
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Location Access Needed"),
        content: const Text(
          "Qibla direction requires your location. "
          "You can enable it anytime in Settings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Geolocator.openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  double _calculateBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _toRad(lat1);
    final phi2 = _toRad(lat2);
    final deltaLon = _toRad(lon2 - lon1);

    final y = math.sin(deltaLon) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLon);

    return (_toDeg(math.atan2(y, x)) + 360) % 360;
  }

  double _toRad(double d) => d * math.pi / 180;
  double _toDeg(double r) => r * 180 / math.pi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Qibla Direction'),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 14, 76, 61),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/qibla_bg.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Container(color: Colors.black.withOpacity(0.25)),
          _granted
              ? (_position == null || _bearingToKaaba == null)
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(
                                compassHorizontalOffset,
                                compassVerticalOffset,
                              ),
                              child: Transform.rotate(
                                angle: _rotationAngle(),
                                child: Image.asset(
                                  'assets/images/compass.png',
                                  width: compassSize,
                                  height: compassSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Qibla: ${_bearingToKaaba!.toStringAsFixed(2)}°',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasCompass
                              ? "Heading: ${_deviceHeading?.toStringAsFixed(0) ?? '--'}°"
                              : "No Compass Sensor (Tilt Mode)",
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 24),
                      ],
                    )
              : Center(
                  child: ElevatedButton(
                    onPressed: _requestPermissionAndInit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e7a43),
                    ),
                    child: const Text(
                      "Enable Location",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  double _rotationAngle() {
    final bearing = _bearingToKaaba ?? 0.0;
    final heading = _hasCompass ? (_deviceHeading ?? 0.0) : _fallbackTilt;
    return -(bearing - heading) * math.pi / 180;
  }
}