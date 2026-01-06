// screens/qibla_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  double? _deviceHeading; // compass degrees
  double? _bearingToKaaba;

  bool _hasCompass = false; // hybrid fix
  double _fallbackTilt = 0; // tilt fallback

  static const double kaabaLat = 21.4225;
  static const double kaabaLng = 39.8262;

  // ========================================================================
  // ADJUST THESE VALUES TO MOVE THE COMPASS
  // ========================================================================
  double compassHorizontalOffset = 0.0;  // Positive = RIGHT, Negative = LEFT
  double compassVerticalOffset = 30.0;   // Positive = DOWN, Negative = UP
  double compassSize = 280.0;             // Size of the compass needle image
  // ========================================================================

  @override
  void initState() {
    super.initState();
    _detectCompassSensor();
    _listenCompass();
    _listenAccelerometer();
    _requestPermissionAndInit();
  }

  // --------------------------------------------------------------------------
  // DETECT COMPASS SENSOR (WORKS ON ALL VERSIONS)
  // --------------------------------------------------------------------------
  void _detectCompassSensor() async {
    try {
      final firstReading = await FlutterCompass.events?.first;
      setState(() {
        _hasCompass = firstReading?.heading != null;
      });
    } catch (e) {
      setState(() => _hasCompass = false);
    }
  }

  // --------------------------------------------------------------------------
  // COMPASS LISTENER
  // --------------------------------------------------------------------------
  void _listenCompass() {
    FlutterCompass.events?.listen((event) {
      if (!_hasCompass) return;
      setState(() {
        _deviceHeading = event.heading;
      });
    });
  }

  // --------------------------------------------------------------------------
  // FALLBACK TILT USING ACCELEROMETER
  // --------------------------------------------------------------------------
  void _listenAccelerometer() {
    accelerometerEvents.listen((AccelerometerEvent e) {
      if (_hasCompass) return;

      final tilt = math.atan2(e.x, e.y);
      setState(() {
        _fallbackTilt = tilt * 180 / math.pi;
      });
    });
  }

  // --------------------------------------------------------------------------
  // LOCATION + BEARING
  // --------------------------------------------------------------------------
  Future<void> _requestPermissionAndInit() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      setState(() => _granted = false);
      return;
    }
    setState(() => _granted = true);

    final pos = await _determinePosition();
    setState(() {
      _position = pos;
      _bearingToKaaba =
          _calculateBearing(pos.latitude, pos.longitude, kaabaLat, kaabaLng);
    });
  }

  Future<Position> _determinePosition() async {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
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

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
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
            child: Image.asset('assets/images/qibla_bg.jpg', fit: BoxFit.cover),
          ),
          Container(color: Colors.black.withOpacity(0.25)),

          _granted
              ? (_position == null || _bearingToKaaba == null)
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // This Expanded takes up the space and centers compass
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
                        // Bottom text information
                        const SizedBox(height: 16),
                        Text(
                          'Qibla: ${_bearingToKaaba!.toStringAsFixed(2)}°',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white),
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
                    child: const Text("Enable Location",
                        style: TextStyle(color: Colors.white)),
                  ),
                )
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ROTATION LOGIC
  // --------------------------------------------------------------------------
  double _rotationAngle() {
    final bearing = _bearingToKaaba ?? 0.0;

    if (_hasCompass) {
      final heading = _deviceHeading ?? 0.0;
      final diff = (bearing - heading);
      return -diff * math.pi / 180;
    } else {
      final heading = _fallbackTilt;
      final diff = (bearing - heading);
      return -diff * math.pi / 180;
    }
  }
}