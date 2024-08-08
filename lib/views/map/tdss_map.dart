import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Marker> _markers = [];
  Set<Polyline> _polylines = {};
  List<Polyline> _attackpolylines = [];
  List<Polyline> _defensivePolylines = [];
  List<Polyline> _finalPerimeterPolylines = [];
  List<Polyline> _defensivePerimeterPolylines = [];
  List<Polyline> _contactPolylines = [];
  List<Polyline> _offensivePolylines = [];
  List<Polyline> _boundaryPolylines = [];
  List<Polyline> _attackPolylines = [];
  List<Polyline> _retreatPolylines = [];
  List<Polyline> defensiveLines = [];
  late LatLng _selectedPosition;
  Map<String, Map<String, String>> _weaponData = {};
  Map<String, Map<String, String>> _unitData = {};
  Map<String, Map<String, String>> _enemyData = {};

  Map<String, LatLng> _unitPositions = {};
  Map<String, LatLng> _weaponPositions = {};
  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      // Load markers data
      String? markersJson = prefs.getString('markers');
      if (markersJson != null) {
        List<dynamic> markersList = jsonDecode(markersJson);
        setState(() {
          _markers = markersList.map<Marker>((marker) {
            LatLng position = LatLng(marker['lat'], marker['lng']);
            String imagePath = marker['imagePath'];
            String type = marker['type'];
            String label = marker['label'];
            if (type == 'Unit') {
              _unitPositions[label] = position;
            } else if (type == 'Weapon') {
              _weaponPositions[label] = position;
            }
            return Marker(
              width: 150.0,
              height: 60.0,
              point: position,
              builder: (ctx) => GestureDetector(
                onTap: () => _showActionDialog(type, position, label),
                onLongPress: () => _showDeleteConfirmationDialog(position),
                child: Column(
                  children: [
                    Image.asset(
                      imagePath,
                      width: 40.0,
                      height: 40.0,
                      key: ValueKey('$imagePath|$type|$label'),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: const Color.fromARGB(255, 0, 0, 0),
                        backgroundColor:
                            const Color.fromARGB(96, 255, 255, 255),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList();
        });
      }

      // Load weapon data
      String? weaponDataJson = prefs.getString('weaponData');
      if (weaponDataJson != null) {
        Map<String, dynamic> rawWeaponData = jsonDecode(weaponDataJson);
        _weaponData = rawWeaponData.map(
            (key, value) => MapEntry(key, Map<String, String>.from(value)));
      }

      // Load unit data
      String? unitDataJson = prefs.getString('unitData');
      if (unitDataJson != null) {
        Map<String, dynamic> rawUnitData = jsonDecode(unitDataJson);
        _unitData = rawUnitData.map(
            (key, value) => MapEntry(key, Map<String, String>.from(value)));
      }

      // Load enemy data
      String? enemyDataJson = prefs.getString('enemyData');
      if (enemyDataJson != null) {
        Map<String, dynamic> rawEnemyData = jsonDecode(enemyDataJson);
        _enemyData = rawEnemyData.map(
            (key, value) => MapEntry(key, Map<String, String>.from(value)));
      }
    } catch (e, stacktrace) {
      print('Error loading data: $e\n$stacktrace');
    }
  }

  Future<void> _saveMarkers() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> markersList = _markers.map((marker) {
        LatLng point = marker.point;
        Widget? child = (marker.builder(context) as GestureDetector).child;
        Key? key = (child as Column).children[0].key;
        String keyString = key?.toString() ?? '';
        List<String> parts = keyString.split('|');
        String imagePath = parts[0].split("'")[1];
        String type = parts[1].split("'")[0];
        String label = parts[2].split("'")[0];
        return {
          'lat': point.latitude,
          'lng': point.longitude,
          'imagePath': imagePath,
          'type': type,
          'label': label,
        };
      }).toList();
      String markersJson = jsonEncode(markersList);
      print('Saving markers: $markersJson');
      prefs.setString('markers', markersJson);

      String weaponDataJson = jsonEncode(_weaponData);
      print('Saving weapon data: $weaponDataJson');
      prefs.setString('weaponData', weaponDataJson);

      String unitDataJson = jsonEncode(_unitData);
      print('Saving unit data: $unitDataJson');
      prefs.setString('unitData', unitDataJson);

      String enemyDataJson = jsonEncode(_enemyData);
      print('Saving enemy data: $enemyDataJson');
      prefs.setString('enemyData', enemyDataJson);

      _loadMarkers();
    } catch (e, stacktrace) {
      print('Error saving markers or weapon data: $e\n$stacktrace');
    }
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedPosition = position;
    });
    _showSelectionDialog();
  }

  void _showSelectionDialog() {
    TextEditingController labelController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Select Icon and Enter Label'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: InputDecoration(labelText: 'Label'),
              ),
              SizedBox(
                height: 300, // Set a fixed height for the scrollable area
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Image.asset('assets/tdss/missile.png',
                            width: 40, height: 40),
                        title: Text('Missile'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/missile.png', 'Weapon',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/122.png',
                            width: 40, height: 40),
                        title: Text('122 MM motor'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/122.png', 'Weapon',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/120MM_motor.png',
                            width: 40, height: 40),
                        title: Text('120 MM motor'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/120MM_motor.png', 'Weapon',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/60 MM_motor.png',
                            width: 40, height: 40),
                        title: Text('60 MM motor'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/60 MM_motor.png', 'Weapon',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/section.png',
                            width: 40, height: 40),
                        title: Text('Section'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/section.png', 'Unit',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/platoon.png',
                            width: 40, height: 40),
                        title: Text('Platoon'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/platoon.png', 'Unit',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/battalion.png',
                            width: 40, height: 40),
                        title: Text('Battalion'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/battalion.png', 'Unit',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/company.png',
                            width: 40, height: 40),
                        title: Text('Company'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/company.png', 'Unit',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                      ListTile(
                        leading: Image.asset('assets/tdss/enemy.png',
                            width: 40, height: 40),
                        title: Text('Enemy'),
                        onTap: () {
                          if (labelController.text.isNotEmpty) {
                            _addMarker('assets/tdss/enemy.png', 'Enemy',
                                labelController.text);
                          } else {
                            _showErrorDialog();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showErrorDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text('Label cannot be empty. Please enter a label.'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _addMarker(String imagePath, String type, String label) {
    Navigator.of(context).pop();
    setState(() {
      _markers.add(
        Marker(
          width: 150.0,
          height: 60.0,
          point: _selectedPosition,
          builder: (ctx) => GestureDetector(
            onTap: () => _showActionDialog(type, _selectedPosition, label),
            onLongPress: () => _showDeleteConfirmationDialog(_selectedPosition),
            child: Column(
              children: [
                Image.asset(
                  imagePath,
                  width: 40.0,
                  height: 40.0,
                  key: ValueKey('$imagePath|$type|$label'),
                ),
                Text(
                  label,
                  style: TextStyle(
                      color: const Color.fromARGB(255, 0, 0, 0),
                      backgroundColor: const Color.fromARGB(96, 255, 255, 255),
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                )
              ],
            ),
          ),
        ),
      );
    });
    _saveMarkers();
  }

  void _showActionDialog(String type, LatLng position, String label) {
    showDialog(
      context: context,
      builder: (context) {
        List<Widget> actions = [];
        if (type == 'Weapon') {
          if (_weaponData.containsKey(label)) {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showWeaponDataDialog(position, label);
                },
                child: Text('View Weapon Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditWeaponDataDialog(position, label);
                },
                child: Text('Edit Weapon Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
            ];
          } else {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showInsertWeaponDataDialog(position, label);
                },
                child: Text('Insert Weapon Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
            ];
          }
          actions.add(
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showFireTestDialog(position);
              },
              child: Text('Fire Test'),
            ),
          );
        } else if (type == 'Unit') {
          if (_unitData.containsKey(label)) {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showUnitDataDialog(position, label);
                },
                child: Text('View Unit Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditUnitDataDialog(position, label);
                },
                child: Text('Edit Unit Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
            ];
          } else {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showInsertUnitDataDialog(position, label);
                },
                child: Text('Insert Unit Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
            ];
          }
          actions.add(
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showFireTestDialog(position);
              },
              child: Text('Fire Test'),
            ),
          );
        } else if (type == 'Enemy') {
          if (_enemyData.containsKey(label)) {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEnemyDataDialog(position, label);
                },
                child: Text('View Enemy Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditEnemyDataDialog(position, label);
                },
                child: Text('Edit Enemy Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
              ElevatedButton(
                onPressed: () {
                  try {
                    Navigator.of(context).pop();
                    double successProbability =
                        _calculateSuccessProbability(label, position);
                    String tactics = _determineTactics(label);
                    _calculateStrategicPolylines(position);
                    _drawAttackPolylines(position);
                    String successProbabilityStr =
                        successProbability.toStringAsFixed(2);

                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text('Attack Calculation'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  'Success Probability: $successProbabilityStr%'),
                              SizedBox(height: 12),
                              Text('Tactics: $tactics'),
                            ],
                          ),
                          actions: [
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  } catch (e) {
                    print('Error: $e');
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text('Error'),
                          content: Text(
                              'An error occurred while calculating success probability. Please ensure all data is properly loaded.'),
                          actions: [
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
                child: Text(
                    'Calculate Success Probability \n and Tactics To Attack'),
              ),
              SizedBox(height: 12, width: 12),
            ];
          } else {
            actions = [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showInsertEnemyDataDialog(position, label);
                },
                child: Text('Insert Enemy Data'),
              ),
              SizedBox(
                height: 12,
                width: 12,
              ),
            ];
          }
        }

        return AlertDialog(
          title: Text('Action'),
          content: Text('Choose an action for the $type marker.'),
          actions: actions,
        );
      },
    );
  }

  void _calculateStrategicPolylines(LatLng enemyPosition) {
    List<Polyline> contactLines = [];
    List<Polyline> defensiveLines = [];
    List<LatLng> contactPoints = [];
    List<LatLng> defensivePoints = [];

    double totalUnitBearing = 0;
    double totalWeaponBearing = 0;
    int unitCount = 0;
    int weaponCount = 0;

    // 1500 meters in front of the enemy (for all units)
    _unitData.forEach((unitLabel, unitInfo) {
      LatLng? unitPosition = _unitPositions[unitLabel];
      if (unitPosition != null) {
        double bearing = _calculateBearing(unitPosition, enemyPosition);
        totalUnitBearing += bearing;
        unitCount++;
        LatLng contactPoint =
            _calculateOffsetPosition(unitPosition, enemyPosition, 1500);
        contactPoints.add(contactPoint);
        contactLines.add(Polyline(
          points: [unitPosition, contactPoint],
          color: Colors.green,
          strokeWidth: 2,
        ));
      }
    });

    // 3000 meters in front of all weapons
    _weaponData.forEach((weaponLabel, weaponInfo) {
      LatLng? weaponPosition = _weaponPositions[weaponLabel];
      if (weaponPosition != null) {
        double bearing = _calculateBearing(weaponPosition, enemyPosition);
        totalWeaponBearing += bearing;
        weaponCount++;
        LatLng defensivePoint =
            _calculateOffsetPosition(weaponPosition, enemyPosition, 3000);
        defensivePoints.add(defensivePoint);
        defensiveLines.add(Polyline(
          points: [weaponPosition, defensivePoint],
          color: Colors.blue,
          strokeWidth: 2,
        ));
      }
    });

    double averageBearing =
        (totalUnitBearing + totalWeaponBearing) / (unitCount + weaponCount);

    // Calculate a point 1000m behind the enemy in the opposite direction of the average bearing
    LatLng pointBehindEnemy = _calculateOffsetPositionWithBearing(
        enemyPosition, averageBearing + pi, 5000);

    // Calculate the diagonal points to draw the 3000m line
    LatLng startPoint = _calculateOffsetPositionWithBearing(
        pointBehindEnemy, averageBearing + (pi / 4), 5000);
    LatLng endPoint = _calculateOffsetPositionWithBearing(
        pointBehindEnemy, averageBearing - (pi / 4), 5000);

    // Add the diagonal line 3000m long, 1000m behind the enemy
    contactLines.add(Polyline(
      points: [startPoint, endPoint],
      color: Colors.red,
      strokeWidth: 2,
    ));

    // Create boundary line for contact points
    if (contactPoints.isNotEmpty) {
      contactLines.add(Polyline(
        points: _createBoundary(contactPoints),
        color: Colors.green,
        strokeWidth: 2,
      ));
    }

    // Create boundary line for defensive points
    if (defensivePoints.isNotEmpty) {
      defensiveLines.add(Polyline(
        points: _createBoundary(defensivePoints),
        color: Colors.blue,
        strokeWidth: 2,
      ));
    }

    // Update the map with the new polylines
    setState(() {
      _defensivePolylines = defensiveLines;
      _contactPolylines = contactLines;
    });
  }

  LatLng _calculateOffsetPositionWithBearing(
      LatLng start, double bearing, double distanceMeters) {
    const double earthRadius = 6371000; // in meters

    double lat1 = _degreesToRadians(start.latitude);
    double lon1 = _degreesToRadians(start.longitude);
    double angularDistance = distanceMeters / earthRadius;

    double newLat = asin(sin(lat1) * cos(angularDistance) +
        cos(lat1) * sin(angularDistance) * cos(bearing));
    double newLon = lon1 +
        atan2(sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(newLat));

    return LatLng(_radiansToDegrees(newLat), _radiansToDegrees(newLon));
  }

  List<LatLng> _createBoundary(List<LatLng> points) {
    points.sort((a, b) {
      return _calculateBearing(LatLng(0, 0), a)
          .compareTo(_calculateBearing(LatLng(0, 0), b));
    });
    points.add(points.first); // Close the loop
    return points;
  }

  LatLng _calculateOffsetPosition(
      LatLng start, LatLng end, double distanceMeters) {
    const double earthRadius = 6371000; // in meters
    double bearing = _calculateBearing(start, end);

    double lat1 = _degreesToRadians(start.latitude);
    double lon1 = _degreesToRadians(start.longitude);
    double angularDistance = distanceMeters / earthRadius;

    double newLat = asin(sin(lat1) * cos(angularDistance) +
        cos(lat1) * sin(angularDistance) * cos(bearing));
    double newLon = lon1 +
        atan2(sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(newLat));

    return LatLng(_radiansToDegrees(newLat), _radiansToDegrees(newLon));
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double lat1 = _degreesToRadians(start.latitude);
    double lon1 = _degreesToRadians(start.longitude);
    double lat2 = _degreesToRadians(end.latitude);
    double lon2 = _degreesToRadians(end.longitude);

    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    return atan2(y, x);
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  double _radiansToDegrees(double radians) {
    return radians * (180.0 / pi);
  }

  void _calculatePerimeterPolylines(LatLng enemyPosition) {
    List<Polyline> finalPerimeterPolylines = [];
    List<Polyline> defensivePerimeterPolylines = [];

    // Calculate the final attack perimeter (300m from the enemy)
    finalPerimeterPolylines
        .add(_createCircle(enemyPosition, 300, Color.fromARGB(255, 7, 1, 61)));

    // Calculate the defensive perimeter (1500m from all weapons)
    List<LatLng> weaponPositions = _weaponData.keys
        .map((weaponLabel) => _weaponPositions[weaponLabel])
        .where((position) => position != null)
        .cast<LatLng>()
        .toList();

    weaponPositions.forEach((weaponPosition) {
      defensivePerimeterPolylines
          .add(_createCircle(weaponPosition, 1500, Colors.green));
    });

    // Update the map with the new perimeters
    setState(() {
      _finalPerimeterPolylines = finalPerimeterPolylines;
      _defensivePerimeterPolylines = defensivePerimeterPolylines;
    });
  }

// Helper method to create a circle polyline
  Polyline _createCircle(LatLng center, double radius, Color color) {
    const int segments = 100; // Number of segments for smoothness
    List<LatLng> points = [];

    for (int i = 0; i <= segments; i++) {
      double angle = (2 * pi * i) / segments;
      double dx = radius * cos(angle);
      double dy = radius * sin(angle);
      points.add(LatLng(
          center.latitude + (dy / 111320),
          center.longitude +
              (dx / (111320 * cos(center.latitude * pi / 180)))));
    }

    return Polyline(
      points: points,
      color: color,
      strokeWidth: 2,
    );
  }

  double _calculateSuccessProbability(String enemyLabel, LatLng position) {
    // Ensure enemy data exists for the given label
    if (!_enemyData.containsKey(enemyLabel)) {
      throw Exception(
          'Unexpected null value: Enemy data for $enemyLabel is null.');
    }

    // Parse enemy data
    Enemy enemy = Enemy(
      name: enemyLabel,
      manpower: int.parse(_enemyData[enemyLabel]?['manpower'] ?? '0'),
      skillLevel: int.parse(_enemyData[enemyLabel]?['skills'] ?? '0'),
      position: position,
    );

    // Initialize variables for cumulative calculations
    double totalProbability = 0;
    int calculationCount = 0;

    // Iterate over all units
    _unitData.forEach((unitLabel, unitInfo) {
      LatLng unitPosition = _unitPositions[unitLabel] ?? LatLng(0, 0);
      Unit unit = Unit(
        name: unitLabel,
        manpower: int.parse(unitInfo['manpower'] ?? '0'),
        skillLevel: int.parse(unitInfo['skills'] ?? '0'),
        position: unitPosition,
      );

      // Iterate over all weapons
      _weaponData.forEach((weaponLabel, weaponInfo) {
        LatLng weaponPosition = _weaponPositions[weaponLabel] ?? LatLng(0, 0);
        Weapon weapon = Weapon(
          name: weaponLabel,
          fireRange: double.parse(weaponInfo['range'] ?? '0'),
          blastRadius: double.parse(weaponInfo['blast'] ?? '0'),
          rounds: int.parse(weaponInfo['rounds'] ?? '0'),
          ammoType: weaponInfo['ammo'] ?? '',
          position: weaponPosition,
        );

        // Example calculation
        double distance = _calculateDistance(unit.position, enemy.position);
        double effectiveness = (weapon.fireRange - distance) / weapon.fireRange;
        effectiveness =
            effectiveness.clamp(0.0, 1.0); // Ensure it's within [0, 1]

        double unitEffectiveness = (unit.skillLevel + unit.manpower) / 2.0;
        double enemyEffectiveness = (enemy.skillLevel + enemy.manpower) / 2.0;

        double probability = (unitEffectiveness * effectiveness) /
            (enemyEffectiveness == 0 ? 1 : enemyEffectiveness) *
            100;

        // Accumulate probability
        totalProbability += probability;
        calculationCount++;
      });
    });

    // Calculate average probability
    if (calculationCount > 0) {
      totalProbability /= calculationCount;
    }

    return totalProbability.clamp(0, 100);
  }

  double _calculateDistance(LatLng position1, LatLng position2) {
    double lat1 = position1.latitude;
    double lon1 = position1.longitude;
    double lat2 = position2.latitude;
    double lon2 = position2.longitude;

    double p = 0.017453292519943295; // Math.PI / 180
    double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;

    return 12742 * asin(sqrt(a)); // 2 * R * asin(sqrt(a))
  }

  String _determineTactics(String enemyLabel) {
    // Example tactics determination logic
    int enemyManpower =
        int.tryParse(_enemyData[enemyLabel]?['manpower'] ?? '0') ?? 0;
    int enemySkills =
        int.tryParse(_enemyData[enemyLabel]?['skills'] ?? '0') ?? 0;

    if (enemyManpower > 300 && enemySkills > 300) {
      return 'Use heavy artillery and air support';
    } else if (enemyManpower > 200) {
      return 'Use artillery and infantry units';
    } else {
      return 'Use infantry units for a direct assault';
    }
  }

  void _drawAttackPolylines(LatLng enemyPosition) {
    List<LatLng> polylinePoints = [];

    // Collect positions from all Weapon and Unit markers and draw polylines directly to the enemy
    for (var marker in _markers) {
      // Extract the label from the marker's key
      Widget? child = (marker.builder(context) as GestureDetector).child;
      Key? key = (child as Column).children[0].key;
      String keyString = key?.toString() ?? '';
      List<String> parts = keyString.split('|');
      String type = parts[1].split("'")[0];

      if (type == 'Weapon' || type == 'Unit') {
        polylinePoints = [marker.point, enemyPosition];
        print('Added marker to polyline: ${marker.point} -> $enemyPosition');

        setState(() {
          _attackpolylines.add(
            Polyline(
              points: polylinePoints,
              strokeWidth: 4.0,
              color: Colors.red,
            ),
          );
        });
      }
    }
  }

  void _calculateDefensiveAndOffensivePolylines(LatLng enemyPosition) {
    List<Polyline> defensivePolylines = [];
    List<Polyline> offensivePolylines = [];
    List<Polyline> retreatPolylines = [];
    List<Polyline> attackPolylines = [];

    LatLng? closestPosition;
    double closestDistance = double.infinity;

    // Create defensive polylines for all units
    _unitData.forEach((unitLabel, unitInfo) {
      LatLng? unitPosition = _unitPositions[unitLabel];
      if (unitPosition != null) {
        Unit unit = Unit(
          name: unitLabel,
          manpower: int.parse(unitInfo['manpower'] ?? '0'),
          skillLevel: int.parse(unitInfo['skills'] ?? '0'),
          position: unitPosition,
        );

        defensivePolylines.add(Polyline(
          points: [unit.position, enemyPosition],
          color: Color.fromARGB(255, 13, 189, 66), // Green color
          strokeWidth: 2,
        ));

        double distance = _calculateDistance(unit.position, enemyPosition);
        if (distance < closestDistance) {
          closestDistance = distance;
          closestPosition = unit.position;
        }
      }
    });

    // Create offensive polylines for all weapons
    _weaponData.forEach((weaponLabel, weaponInfo) {
      LatLng? weaponPosition = _weaponPositions[weaponLabel];
      if (weaponPosition != null) {
        Weapon weapon = Weapon(
          name: weaponLabel,
          fireRange: double.parse(weaponInfo['range'] ?? '0'),
          blastRadius: double.parse(weaponInfo['blast'] ?? '0'),
          rounds: int.parse(weaponInfo['rounds'] ?? '0'),
          ammoType: weaponInfo['ammo'] ?? '',
          position: weaponPosition,
        );

        offensivePolylines.add(Polyline(
          points: [enemyPosition, weapon.position],
          color: Colors.blue,
          strokeWidth: 2,
        ));

        double distance = _calculateDistance(weapon.position, enemyPosition);
        if (distance < closestDistance) {
          closestDistance = distance;
          closestPosition = weapon.position;
        }
      }
    });

    // Draw the attack line (close-range)
    if (closestPosition != null) {
      attackPolylines.add(Polyline(
        points: [enemyPosition, closestPosition!],
        color: Colors.red, // Red color for the attack line
        strokeWidth: 3,
      ));
    }

    // Draw the retreat line (counterattack)
    LatLng retreatPosition = _calculateRetreatPosition(enemyPosition);
    retreatPolylines.add(Polyline(
      points: [enemyPosition, retreatPosition],
      color: Colors.orange, // Orange color for the retreat line
      strokeWidth: 3,
    ));

    setState(() {
      _defensivePolylines = defensivePolylines;
      _offensivePolylines = offensivePolylines;
      _attackPolylines = attackPolylines;
      _retreatPolylines = retreatPolylines;
    });
  }

  LatLng _calculateRetreatPosition(LatLng enemyPosition) {
    // Example retreat logic: Move 0.01 latitude and 0.01 longitude away from the enemy
    return LatLng(
        enemyPosition.latitude + 0.01, enemyPosition.longitude + 0.01);
  }

  void _calculateBoundaryPolylines(LatLng enemyPosition) {
    List<Polyline> defensivePolylines = [];
    List<Polyline> offensivePolylines = [];

    // **Defensive Perimeter**
    List<LatLng> unitPositions = _unitData.keys
        .map((unitLabel) => _unitPositions[unitLabel])
        .where((position) => position != null)
        .cast<LatLng>()
        .toList();

    if (unitPositions.isNotEmpty) {
      // Create a perimeter around the units
      for (int i = 0; i < unitPositions.length; i++) {
        LatLng start = unitPositions[i];
        LatLng end = unitPositions[(i + 1) % unitPositions.length];
        defensivePolylines.add(Polyline(
          points: [start, end],
          color: Colors.green,
          strokeWidth: 2,
        ));
      }

      // Add lines from each unit to the enemy position
      unitPositions.forEach((unitPosition) {
        defensivePolylines.add(Polyline(
          points: [unitPosition, enemyPosition],
          color: Colors.green,
          strokeWidth: 2,
          // Optionally: add dashed pattern for emphasis
        ));
      });
    }

    // **Offensive Perimeter**
    List<LatLng> weaponPositions = _weaponData.keys
        .map((weaponLabel) => _weaponPositions[weaponLabel])
        .where((position) => position != null)
        .cast<LatLng>()
        .toList();

    if (weaponPositions.isNotEmpty) {
      // Create a perimeter around the weapons
      for (int i = 0; i < weaponPositions.length; i++) {
        LatLng start = weaponPositions[i];
        LatLng end = weaponPositions[(i + 1) % weaponPositions.length];
        offensivePolylines.add(Polyline(
          points: [start, end],
          color: Colors.blue,
          strokeWidth: 2,
        ));
      }

      // Add lines from enemy position to each weapon
      weaponPositions.forEach((weaponPosition) {
        offensivePolylines.add(Polyline(
          points: [enemyPosition, weaponPosition],
          color: Colors.blue,
          strokeWidth: 2,
          // Optionally: add dashed pattern for emphasis
        ));
      });
    }

    // Update the map with the new polylines
    setState(() {
      _defensivePolylines = defensivePolylines;
      _offensivePolylines = offensivePolylines;
    });
  }

  void _showInsertUnitDataDialog(LatLng position, String label) {
    final manpowerController = TextEditingController();
    final SkillController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Insert Unit Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: manpowerController,
                decoration: InputDecoration(labelText: 'Manpower'),
              ),
              TextField(
                controller: SkillController,
                decoration: InputDecoration(labelText: 'Skills'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (manpowerController.text.isNotEmpty &&
                      SkillController.text.isNotEmpty) {
                    _unitData[label] = {
                      'manpower': manpowerController.text,
                      'skills': SkillController.text,
                    };
                  } else {
                    _showErrorDialog();
                  }
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showInsertEnemyDataDialog(LatLng position, String label) {
    final manpowerController = TextEditingController();
    final SkillController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Insert Enemy Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: manpowerController,
                decoration: InputDecoration(labelText: 'Manpower'),
              ),
              TextField(
                controller: SkillController,
                decoration: InputDecoration(labelText: 'Skills'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  if (manpowerController.text.isNotEmpty &&
                      SkillController.text.isNotEmpty) {
                    _enemyData[label] = {
                      'manpower': manpowerController.text,
                      'skills': SkillController.text,
                    };
                  } else {
                    _showErrorDialog();
                  }
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showInsertWeaponDataDialog(LatLng position, String label) {
    final rangeController = TextEditingController();
    final blastController = TextEditingController();
    final roundsController = TextEditingController();
    final ammoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Insert Weapon Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rangeController,
                decoration: InputDecoration(labelText: 'Range'),
              ),
              TextField(
                controller: blastController,
                decoration: InputDecoration(labelText: 'Blast Radius'),
              ),
              TextField(
                controller: roundsController,
                decoration: InputDecoration(labelText: 'Rounds'),
              ),
              TextField(
                controller: ammoController,
                decoration: InputDecoration(labelText: 'Ammo Type'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _weaponData[label] = {
                    'range': rangeController.text,
                    'blast': blastController.text,
                    'rounds': roundsController.text,
                    'ammo': ammoController.text,
                  };
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showEditWeaponDataDialog(LatLng position, String label) {
    final weapon = _weaponData[label] ?? {};
    final rangeController = TextEditingController(text: weapon['range']);
    final blastController = TextEditingController(text: weapon['blast']);
    final roundsController = TextEditingController(text: weapon['rounds']);
    final ammoController = TextEditingController(text: weapon['ammo']);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Weapon Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rangeController,
                decoration: InputDecoration(labelText: 'Range'),
              ),
              TextField(
                controller: blastController,
                decoration: InputDecoration(labelText: 'Blast Radius'),
              ),
              TextField(
                controller: roundsController,
                decoration: InputDecoration(labelText: 'Rounds'),
              ),
              TextField(
                controller: ammoController,
                decoration: InputDecoration(labelText: 'Ammo Type'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _weaponData[label] = {
                    'range': rangeController.text,
                    'blast': blastController.text,
                    'rounds': roundsController.text,
                    'ammo': ammoController.text,
                  };
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showEditUnitDataDialog(LatLng position, String label) {
    final unit = _unitData[label] ?? {};
    final manpowerController = TextEditingController(text: unit['manpower']);
    final SkillController = TextEditingController(text: unit['skills']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Unit Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: manpowerController,
                decoration: InputDecoration(labelText: 'Man Power'),
              ),
              TextField(
                controller: SkillController,
                decoration: InputDecoration(labelText: 'Skills'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _unitData[label] = {
                    'manpower': manpowerController.text,
                    'skills': SkillController.text,
                  };
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showEditEnemyDataDialog(LatLng position, String label) {
    final enemy = _enemyData[label] ?? {};
    final manpowerController = TextEditingController(text: enemy['manpower']);
    final SkillController = TextEditingController(text: enemy['skills']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Enemy Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: manpowerController,
                decoration: InputDecoration(labelText: 'Man Power'),
              ),
              TextField(
                controller: SkillController,
                decoration: InputDecoration(labelText: 'Skills'),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _enemyData[label] = {
                    'manpower': manpowerController.text,
                    'skills': SkillController.text,
                  };
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Save'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showWeaponDataDialog(LatLng position, String label) {
    final weapon = _weaponData[label];
    if (weapon == null) return; // No data to show

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Weapon Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Range: ${weapon['range']}'),
              Text('Blast Radius: ${weapon['blast']}'),
              Text('Rounds: ${weapon['rounds']}'),
              Text('Ammo Type: ${weapon['ammo']}'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditWeaponDataDialog(position, label);
              },
              child: Text('Edit Weapon Data'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showUnitDataDialog(LatLng position, String label) {
    final unit = _unitData[label];
    if (unit == null) return; // No data to show

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Weapon Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Manpower: ${unit['manpower']}'),
              Text('Skills: ${unit['skills']}'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditUnitDataDialog(position, label);
              },
              child: Text('Edit Unit Data'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showEnemyDataDialog(LatLng position, String label) {
    final enemy = _enemyData[label];
    if (enemy == null) return; // No data to show

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Weapon Data'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Manpower: ${enemy['manpower']}'),
              Text('Skills: ${enemy['skills']}'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditEnemyDataDialog(position, label);
              },
              child: Text('Edit Enemy Data'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showFireTestDialog(LatLng position) {
    TextEditingController millsController = TextEditingController();
    TextEditingController distanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Fire Test'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: millsController,
                decoration: InputDecoration(labelText: 'Mills (0 to 6399)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: distanceController,
                decoration: InputDecoration(labelText: 'Distance (meters)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                int mills = int.parse(millsController.text);
                double distance = double.parse(distanceController.text);
                _calculateExplosion(position, mills, distance);
                Navigator.of(context).pop();
              },
              child: Text('Fire'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(LatLng position) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete Marker'),
          content: Text('Are you sure you want to delete this marker?'),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {
                  // Find the marker to be deleted
                  var markerToDelete =
                      _markers.firstWhere((marker) => marker.point == position);

                  // Extract the label from the marker's key
                  Widget? child =
                      (markerToDelete.builder(context) as GestureDetector)
                          .child;
                  Key? key = (child as Column).children[0].key;
                  String keyString = key?.toString() ?? '';
                  List<String> parts = keyString.split('|');
                  String label = parts[2].split("'")[0];

                  // Remove the marker
                  _markers.removeWhere((marker) => marker.point == position);
                  // Remove any polylines containing the marker position
                  _polylines.removeWhere(
                      (polyline) => polyline.points.contains(position));

                  // Remove associated weapon and unit data
                  _weaponData.remove(label);
                  _unitData.remove(label);
                });
                _saveMarkers();
                Navigator.of(context).pop();
              },
              child: Text('Delete'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _calculateExplosion(LatLng position, int mills, double distance) {
    // Example calculation for explosion position
    double radians = mills * (math.pi * 2) / 6400;
    double dx = distance * math.cos(radians);
    double dy = distance * math.sin(radians);

    LatLng explosionPosition = LatLng(
      position.latitude + (dx / 111320), // Approximate meters per degree
      position.longitude +
          (dy / (111320 * math.cos(position.latitude * math.pi / 180))),
    );

    setState(() {
      // Add firing path
      _polylines.add(Polyline(
        points: [position, explosionPosition],
        strokeWidth: 4.0,
        color: Colors.red,
      ));

      // Add marker for the explosion place
      _markers.add(Marker(
        width: 40.0,
        height: 40.0,
        point: explosionPosition,
        builder: (ctx) => Image.asset(
          'assets/tdss/explosion.png',
          width: 40.0,
          height: 40.0,
        ),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Combine all polylines into one list
    List<Polyline> allPolylines = []
      ..addAll(_polylines)
      // ..addAll(_attackpolylines)
      ..addAll(_defensivePolylines)
      ..addAll(_offensivePolylines)
      ..addAll(_attackPolylines)
      ..addAll(_retreatPolylines)
      ..addAll(_boundaryPolylines)
      ..addAll(_finalPerimeterPolylines)
      ..addAll(_defensivePerimeterPolylines)
      ..addAll(_contactPolylines)
      ..addAll(defensiveLines);

    return Scaffold(
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(51.5, -0.09),
          zoom: 13.0,
          onTap: (tapPosition, latLng) {
            _onMapTap(latLng);
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          PolylineLayer(
            polylines: allPolylines,
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}

class CustomMarker {
  final LatLng position;
  final String type;
  final String label;

  CustomMarker(
      {required this.position, required this.type, required this.label});
}

class Enemy {
  String name;
  int manpower;
  int skillLevel;
  LatLng position;

  Enemy(
      {required this.name,
      required this.manpower,
      required this.skillLevel,
      required this.position});
}

class Unit {
  final String name;
  final int manpower;
  final int skillLevel;
  final LatLng position;

  Unit({
    required this.name,
    required this.manpower,
    required this.skillLevel,
    required this.position,
  });
}

class Weapon {
  final String name;
  final double fireRange;
  final double blastRadius;
  final int rounds;
  final String ammoType;
  final LatLng position;

  Weapon({
    required this.name,
    required this.fireRange,
    required this.blastRadius,
    required this.rounds,
    required this.ammoType,
    required this.position,
  });
}
