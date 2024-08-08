import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity/connectivity.dart';
import 'package:military_admin/colors.dart';
import 'package:military_admin/images.dart';
import 'package:military_admin/styles.dart';
import 'package:military_admin/views/map/operation_map.dart';
import 'package:military_admin/views/map/weapon.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:velocity_x/velocity_x.dart';
import 'package:vector_math/vector_math.dart' as vectorMath;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

typedef DecoderCallback = Future<ui.Codec> Function(ImmutableBuffer buffer,
    {int? cacheWidth, int? cacheHeight, bool? allowUpscaling});

class CachedTileProvider extends TileProvider {
  final cacheManager = DefaultCacheManager();

  @override
  ImageProvider getImage(Coords<num> coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CustomCachedNetworkImageProvider(url, cacheManager: cacheManager);
  }

  String getTileUrl(Coords<num> coordinates, TileLayer options) {
    final tileUrl = options.urlTemplate!
        .replaceAll(
            '{s}',
            options.subdomains[(coordinates.x.toInt() + coordinates.y.toInt()) %
                options.subdomains.length])
        .replaceAll('{z}', '${coordinates.z.toInt()}')
        .replaceAll('{x}', '${coordinates.x.toInt()}')
        .replaceAll('{y}', '${coordinates.y.toInt()}');
    return tileUrl;
  }
}

class CustomCachedNetworkImageProvider
    extends ImageProvider<CustomCachedNetworkImageProvider> {
  final String url;
  final BaseCacheManager cacheManager;

  CustomCachedNetworkImageProvider(this.url, {required this.cacheManager});

  @override
  Future<CustomCachedNetworkImageProvider> obtainKey(
      ImageConfiguration configuration) {
    return SynchronousFuture<CustomCachedNetworkImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      CustomCachedNetworkImageProvider key,
      Future<ui.Codec> Function(ImmutableBuffer,
              {TargetImageSize Function(int, int)? getTargetSize})
          decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('URL', url),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
      CustomCachedNetworkImageProvider key,
      Future<ui.Codec> Function(ImmutableBuffer,
              {TargetImageSize Function(int, int)? getTargetSize})
          decode) async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult != ConnectivityResult.none) {
        // Online: Load and cache the image
        final FileInfo? fileInfo = await cacheManager.getFileFromCache(url);
        if (fileInfo == null || fileInfo.file == null) {
          // Download and cache the file if not present
          final Uint8List? imageData = await cacheManager
              .getSingleFile(url)
              .then((file) => file.readAsBytes());
          if (imageData != null) {
            return decode(await ImmutableBuffer.fromUint8List(imageData));
          } else {
            throw Exception('Failed to load image data.');
          }
        } else {
          // Load from cache
          final bytes = await fileInfo.file.readAsBytes();
          return decode(
              await ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes)));
        }
      } else {
        // Offline: Load from cache
        final file = await cacheManager.getFileFromCache(url);
        if (file?.file != null) {
          final bytes = await file!.file.readAsBytes();
          return decode(
              await ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes)));
        } else {
          throw Exception('Offline and image not found in cache.');
        }
      }
    } catch (e) {
      throw Exception('Failed to load image: $e');
    }
  }
}

class Tdss extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<Tdss> {
  LatLng? _currentLocation;
  LatLng? _dotLocation;
  final double _zoom = 13.0;
  final double _dotSize = 12.0;
  double _bearing = 0.0;
  final MapController _mapController = MapController();
  String _mapType = 'offline';
  bool _isOnline = true;
  List<Map<String, dynamic>> _locations = [];
  String _mgrsString = '';
  TextEditingController _searchController = TextEditingController();
  TextEditingController _deletecontroller = TextEditingController();
  bool _drawCircle = false;
  bool _isMapReady = false;
  double _circleRadius = 4600;
  List<Map<String, dynamic>> _circles = [];
  List<LatLng> _targets = [];
  LatLng? _targetLocation1;
  LatLng? _targetLocation2;
  double _targetDistance = 0.0;
  bool _targetsSet = false;
  List<LatLng> points = [];
  double? distance;
  bool isTargetMode = false; // List to hold points for drawing polyline
  double _totalDistance = 0.0;
  String _selectedColor = 'blue';
  List<Map<String, dynamic>> _nearestLocations = [];
  List<Polyline> _mapPolylines = [];
  double? bearingInMils;
  bool _showMgrsGrid = false; // Add this state variable
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
  Map<String, LatLng> _enemyPositions = {};

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    fetchLocations();
    _loadSavedLocations(); // Load saved locations when the screen loads
    _setupConnectivityListener();
    _loadMarkers();

    _mapController.mapEventStream.listen((event) {
      if (event is MapEventMove || event is MapEventMoveEnd) {
        setState(() {
          _dotLocation = event.center;
          if (_dotLocation != null) {
            _updateMGRS(_dotLocation!);
          }
        });
      }
    });
  }

  void _toggleOnlineMode() {
    setState(() {
      _isOnline = !_isOnline;
    });
  }

  void _calculateSuitableWeapons() {
    _nearestLocations = _nearestLocations.map((loc) {
      final suitableWeapons = weapons.where((weapon) {
        return (loc['distance'] - 20) <= weapon.range &&
            weapon.range <= (loc['distance'] + 20);
      }).toList();

      return {
        ...loc,
        'suitableWeapons': suitableWeapons,
      };
    }).toList();
  }

  void _findNearestLocations(LatLng tappedLocation) {
    final distance = Distance();

    List<Map<String, dynamic>> blueLocations = _locations.where((location) {
      final colorName = location['color']?.toLowerCase() ?? '';
      return colorName == 'blue';
    }).toList();

    List<Map<String, dynamic>> distances = blueLocations.map((location) {
      final latitude = double.tryParse(location['latitude']) ?? 0.0;
      final longitude = double.tryParse(location['longitude']) ?? 0.0;
      final point = LatLng(latitude, longitude);
      final dist = distance.as(LengthUnit.Meter, tappedLocation, point);
      return {
        'label': location['label'],
        'distance': dist,
        'point': point,
        'suitableWeapons': [], // Initialize with empty list
      };
    }).toList();

    distances.sort((a, b) => a['distance'].compareTo(b['distance']));

    setState(() {
      _nearestLocations = distances.take(3).toList();
      _calculateSuitableWeapons();
      _drawRoutes(tappedLocation);
    });
  }

  void _drawRoutes(LatLng tappedLocation) {
    List<Polyline> polylines = _nearestLocations.map((loc) {
      final start = loc['point'];
      final end = tappedLocation;
      final waypoints = _generateWaypoints(start, end);
      return Polyline(
        points: waypoints,
        strokeWidth: 4.0,
        color: Colors.blue,
      );
    }).toList();

    setState(() {
      _mapPolylines = polylines;
    });
  }

  List<LatLng> _generateWaypoints(LatLng start, LatLng end) {
    List<LatLng> waypoints = [];
    const numSteps = 5; // Number of steps in the zigzag pattern

    double latStep = (end.latitude - start.latitude) / numSteps;
    double lngStep = (end.longitude - start.longitude) / numSteps;

    for (int i = 0; i <= numSteps; i++) {
      double offsetLat = start.latitude + i * latStep;
      double offsetLng = start.longitude + i * lngStep;

      // Add an offset for the zigzag effect
      if (i % 2 == 0) {
        offsetLat += 0.001; // Adjust as necessary for a noticeable zigzag
      } else {
        offsetLng += 0.001; // Adjust as necessary for a noticeable zigzag
      }

      waypoints.add(LatLng(offsetLat, offsetLng));
    }

    waypoints.add(end); // Ensure the route ends at the destination
    return waypoints;
  }

  void _toggleTargetMode() {
    setState(() {
      isTargetMode = !isTargetMode;
      if (!isTargetMode) {
        points.clear();
        _mapPolylines.clear();
        distance = null;
      }
    });
  }

  LatLng _getMidPoint() {
    if (points.length < 2) return LatLng(0, 0);
    final lat = (points[0].latitude + points[1].latitude) / 2;
    final lon = (points[0].longitude + points[1].longitude) / 2;
    return LatLng(lat, lon);
  }

  Future<void> fetchLocations() async {
    String uri = "http://militarycommand.atwebpages.com/all_location.php";

    try {
      var response = await http.get(Uri.parse(uri));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _locations = List<Map<String, dynamic>>.from(data);
        });
        await _saveLocations(); // Save locations after fetching
      } else {
        throw Exception('Failed to load locations');
      }
    } catch (error) {
      print('Error fetching locations: $error');
    }
  }

  Future<void> _loadSavedLocations() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedLocations = prefs.getString('locations');
    if (savedLocations != null && savedLocations.isNotEmpty) {
      setState(() {
        _locations =
            List<Map<String, dynamic>>.from(json.decode(savedLocations));
      });
      print('Loaded saved locations: $_locations');
    } else {
      print('No saved locations found');
    }
  }

  Future<void> _saveLocations() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('locations', json.encode(_locations));
    print('Locations saved');
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.none) {
        // Handle offline mode
        print('No internet connection');
        _loadSavedLocations(); // Load saved locations when offline
      } else {
        // Handle online mode
        print('Connected to internet');
        fetchLocations(); // Re-fetch locations when online
      }
    });
  }

  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

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
            } else if (type == 'Enemy') {
              _enemyPositions[label] = position;
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

        // Populate _enemyPositions
        _enemyData.forEach((label, data) {
          // Assuming enemy positions are part of the markers
          LatLng? position = _markers
              .firstWhere(
                (marker) => marker.point == _enemyPositions[label],
                orElse: () => Marker(
                  point: LatLng(0.0, 0.0),
                  builder: (ctx) => SizedBox.shrink(),
                ),
              )
              .point;

          if (position != null) {
            _enemyPositions[label] = position;
          }
        });
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
                height: 250, // Set a fixed height for the scrollable area
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
                    String successProbabilityStr =
                        successProbability.toStringAsFixed(2);
                    String tactics = _determineTactics(successProbability);
                    _calculateStrategicPolylines(position);
                    _drawAttackPolylines(position);

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

    // 500 meters in front of the enemy for all units
    _unitData.forEach((unitLabel, unitInfo) {
      LatLng? unitPosition = _unitPositions[unitLabel];
      if (unitPosition != null) {
        double bearing = _calculateBearing(unitPosition, enemyPosition);
        totalUnitBearing += bearing;
        unitCount++;
        LatLng contactPoint =
            _calculateOffsetPosition(unitPosition, enemyPosition, 500);
        contactPoints.add(contactPoint);
        contactLines.add(Polyline(
          points: [unitPosition, contactPoint],
          color: Colors.green,
          strokeWidth: 2,
        ));
      }
    });

    // 1000 meters in front of all weapons
    _weaponData.forEach((weaponLabel, weaponInfo) {
      LatLng? weaponPosition = _weaponPositions[weaponLabel];
      if (weaponPosition != null) {
        double bearing = _calculateBearing(weaponPosition, enemyPosition);
        totalWeaponBearing += bearing;
        weaponCount++;
        LatLng defensivePoint =
            _calculateOffsetPosition(weaponPosition, enemyPosition, 1000);
        defensivePoints.add(defensivePoint);
        defensiveLines.add(Polyline(
          points: [weaponPosition, defensivePoint],
          color: Colors.blue,
          strokeWidth: 2,
        ));
      }
    });

    // Calculate average bearing for units and weapons
    double averageBearing =
        (totalUnitBearing + totalWeaponBearing) / (unitCount + weaponCount);

    // Create a hexagon around the enemy at a distance of 1000 meters
    List<LatLng> hexagonPoints = [];
    double distance = 1000.0; // 1000 meters
    for (int i = 0; i < 6; i++) {
      double bearing = i * (pi / 3); // 60 degrees per side
      hexagonPoints.add(_calculateOffsetPositionWithBearing(
          enemyPosition, bearing, distance));
    }
    hexagonPoints.add(hexagonPoints[0]); // Close the hexagon

    // Add the hexagon polygon
    contactLines.add(Polyline(
      points: hexagonPoints,
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

  double _calculateSuccessProbability(String enemyLabel, LatLng enemyPosition) {
    try {
      // Retrieve enemy data
      Map<String, String>? enemy = _enemyData[enemyLabel];
      if (enemy == null) {
        throw Exception('Enemy data not found for $enemyLabel');
      }

      // Calculate enemy strength
      int enemyManpower = int.parse(enemy['manpower']!);
      int enemySkills = int.parse(enemy['skills']!);
      double enemyStrength = enemyManpower.toDouble() * enemySkills.toDouble();

      // Calculate total unit strength
      double totalUnitStrength = 0.0;
      _unitData.forEach((unitLabel, unit) {
        int unitManpower = int.parse(unit['manpower']!);
        int unitSkills = int.parse(unit['skills']!);
        double unitStrength = unitManpower.toDouble() * unitSkills.toDouble();
        totalUnitStrength += unitStrength;
      });

      double totalWeaponEffectiveness = 0.0;
      Map<String, double> affectedEnemies =
          {}; // To keep track of affected enemies

      _weaponPositions.forEach((weaponLabel, weaponPosition) {
        Map<String, String>? weapon = _weaponData[weaponLabel];
        if (weapon != null) {
          int weaponRange = int.parse(weapon['range']!);
          int weaponBlast = int.parse(weapon['blast']!);

          // Calculate weapon effectiveness
          _enemyData.forEach((affectedEnemyLabel, affectedEnemy) {
            LatLng affectedEnemyPosition =
                _getEnemyPosition(affectedEnemyLabel);

            double distanceToEnemy =
                _calculateDistance(weaponPosition, affectedEnemyPosition);
            if (distanceToEnemy <= weaponRange) {
              // Calculate affected enemy's strength
              double affectedEnemyStrength =
                  int.parse(affectedEnemy['manpower']!) *
                      int.parse(affectedEnemy['skills']!).toDouble();
              totalWeaponEffectiveness += weaponBlast.toDouble();

              // Track affected enemies
              if (affectedEnemies.containsKey(affectedEnemyLabel)) {
                affectedEnemies[affectedEnemyLabel] =
                    (affectedEnemies[affectedEnemyLabel]! +
                        weaponBlast.toDouble());
              } else {
                affectedEnemies[affectedEnemyLabel] = weaponBlast.toDouble();
              }
            }
          });
        }
      });

      // Reduce enemy strength based on the total weapon effectiveness and affected enemies
      double totalEffectiveDamage = 0.0;
      affectedEnemies.forEach((affectedEnemyLabel, damage) {
        Map<String, String>? affectedEnemy = _enemyData[affectedEnemyLabel];
        if (affectedEnemy != null) {
          double affectedEnemyStrength = int.parse(affectedEnemy['manpower']!) *
              int.parse(affectedEnemy['skills']!).toDouble();
          double reducedStrength = affectedEnemyStrength - damage;
          if (reducedStrength < 0) {
            reducedStrength = 0;
          }
          totalEffectiveDamage += (affectedEnemyStrength - reducedStrength);
        }
      });

      double modifiedEnemyStrength = enemyStrength - totalEffectiveDamage;
      if (modifiedEnemyStrength < 0) {
        modifiedEnemyStrength = 0;
      }

      // Calculate success probability based on the modified enemy strength
      double successProbability =
          (totalUnitStrength / (totalUnitStrength + modifiedEnemyStrength)) *
              100;

      return successProbability;
    } catch (e) {
      print('Error calculating success probability: $e');
      return 0.0; // Return 0.0 in case of error
    }
  }

  LatLng _getEnemyPosition(String enemyLabel) {
    // Retrieve the position of an enemy
    return _enemyPositions[enemyLabel]!;
  }

  double _calculatesuceessDistance(LatLng position1, LatLng position2) {
    const double earthRadius = 6371000; // meters
    double lat1 = position1.latitude * (pi / 180.0);
    double lon1 = position1.longitude * (pi / 180.0);
    double lat2 = position2.latitude * (pi / 180.0);
    double lon2 = position2.longitude * (pi / 180.0);

    double dlat = lat2 - lat1;
    double dlon = lon2 - lon1;

    double a =
        pow(sin(dlat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dlon / 2), 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
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

  String _determineTactics(double probability) {
    if (probability < 50) {
      return 'Use heavy artillery and air support';
    } else if (probability < 75) {
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
  void dispose() {
    _connectivitySubscription?.cancel();
    _searchController.dispose();
    super.dispose();
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
      drawer: _buildDrawer(context),
      body: Builder(
        builder: (context) {
          return GestureDetector(
            // onTap: () {
            //   _showOptionsBottomSheet(context);
            // },
            child: _currentLocation != null
                ? Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          center: _currentLocation!,
                          zoom: _zoom,
                          maxZoom: 18.0, // Limit max zoom level
                          minZoom: 7.0, // Limit min zoom level
                          onMapReady: () {
                            setState(() {
                              _isMapReady = true;
                            });
                          },
                          onPositionChanged: (position, _) {
                            setState(() {
                              _dotLocation = position.center;
                              if (_dotLocation != null) {
                                _updateMGRS(_dotLocation!);
                              }
                              if (position.zoom != null) {
                                if (position.zoom! > 9) {
                                  // _showMgrsGrid = true;
                                } else {
                                  _showMgrsGrid = false;
                                }
                                if (position.zoom! > 16 && _isOnline) {
                                  _toggleOnlineMode();
                                } else if (position.zoom! <= 16 && !_isOnline) {
                                  _toggleOnlineMode();
                                }
                              }
                            });
                          },
                          // onTap: (tapPosition, latLng) => _addPoint(latLng),
                          onTap: (tapPosition, latLng) {
                            _onMapTap(latLng);
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: _getMapTypeUrl(),
                            subdomains: ['a', 'b', 'c'],
                            tileProvider: _isOnline
                                ? CachedTileProvider()
                                : CachedTileProvider(),
                          ),
                          MarkerLayer(
                            markers: _buildCircleCenters() +
                                (_showMgrsGrid ? createGridLabels() : []) +
                                _markers,
                          ),
                          PolylineLayer(
                              polylines: allPolylines +
                                  (_showMgrsGrid ? createMgrsGrid() : [])
                              // [
                              //   Polyline(
                              //     points: points,
                              //     strokeWidth: 4.0,
                              //     color: ui.Color.fromARGB(187, 236, 96, 71),
                              //   ),
                              // ] +

                              ),
                          CircleLayer(
                            circles: _buildCircles(),
                          ),
                        ],
                      ),

                      Positioned(
                        top: 16.0,
                        right: 16.0,
                        child: GestureDetector(
                          onTap: _rotateMapToNorthSouth,
                          child: Transform.rotate(
                            angle: 0.0,
                            child: Icon(Icons.navigation, size: 32.0),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).size.height / 2.15 -
                            _dotSize / 2,
                        left: MediaQuery.of(context).size.width / 2 -
                            _dotSize / 2,
                        child: GestureDetector(
                          onTap: () {
                            // _showOptionsBottomSheet(context);
                          },
                          child: Container(
                            width: _dotSize,
                            height: _dotSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16.0,
                        left: 16.0,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: ui.Color.fromARGB(190, 38, 158, 14)),
                          child: Text(
                            _mgrsString,
                            style: TextStyle(
                                fontSize: 16.0,
                                color:
                                    const ui.Color.fromARGB(255, 255, 255, 255),
                                fontFamily: semibold),
                          ),
                        ),
                      ),
                      if (distance != null)
                        Positioned(
                          top: 50.0,
                          left: 20,
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Color.fromARGB(157, 43, 71, 228)),
                            child: Text(
                              'အကွာအဝေး : ${(distance! / 1000).toStringAsFixed(2)} km\n'
                              'ညွန်းရပ်မေးလ်: ${(bearingInMils!).toStringAsFixed(2)} မေလ်း',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 16.0,
                                  color: const ui.Color.fromARGB(
                                      255, 230, 224, 224)),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 16.0,
                        left: 16.0,
                        child: GestureDetector(
                          onTap: _toggleOnlineMode,
                          child: Icon(Icons.map, size: 32.0),
                        ),
                      ),
                      Positioned(
                        right: -15.0,
                        top: MediaQuery.of(context).size.height / 2 - 24,
                        child: FloatingActionButton(
                          onPressed: () {
                            Scaffold.of(context).openDrawer();
                          },
                          child: Icon(Icons.menu),
                        ),
                      ),
                      //  Positioned(
                      //   bottom: 150.0,
                      //   right: 16.0,
                      //   child: FloatingActionButton(
                      //     onPressed: _toggleTargetMode,
                      //     child: Icon(isTargetMode ? Icons.cancel : Icons.gps_fixed),
                      //   ),
                      // ),
                      if (_nearestLocations.isNotEmpty)
                        Positioned(
                          bottom: 140.0,
                          left: 16.0,
                          right:
                              16.0, // Add this line to limit the width of the container
                          child: Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: ui.Color.fromARGB(158, 12, 10, 143)
                                    .withOpacity(0.8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'အနီးဆုံးရောက်ရှိနေသည့်တပ်များ',
                                      style: TextStyle(
                                          fontSize: 16.0,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close,
                                          color: Colors.white),
                                      onPressed: () {
                                        setState(() {
                                          _nearestLocations.clear();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                ..._nearestLocations.map((loc) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom:
                                            15.0), // Add bottom margin between locations
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 8.0),
                                          child: Text(
                                            '${loc['label']}: ${(loc['distance'] / 1000).toStringAsFixed(2)} km',
                                            style: TextStyle(
                                                fontSize: 16.0,
                                                color: Colors.white),
                                          ),
                                        ),
                                        Text(
                                          'ရောက်ရှိနိုင်သောအကူပစ်လက်နက်ကြီးများ',
                                          style: TextStyle(
                                              fontSize: 14.0,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        ...loc['suitableWeapons']
                                            .map<Widget>((weapon) {
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom:
                                                    8.0), // Add padding between weapon details
                                            child: RichText(
                                              text: TextSpan(
                                                text:
                                                    'အမျိုးအစား: ${weapon.name}, တာဝေး: ${weapon.range} မီတာ, ကျည်ပျံသန်းချိန်: ${weapon.bulletFlightTime}စက္ကန့်, ယမ်းအား: ${weapon.gunPower}, တာဝေးမေးလ်: ${weapon.longDistance} မေလ်း',
                                                style: TextStyle(
                                                    fontSize: 14.0,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        )

                      // ..._buildDeleteButtons(),
                    ],
                  )
                : Center(
                    child: CircularProgressIndicator(),
                  ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: _clearAllpollylines,
            child: Icon(isTargetMode ? Icons.cancel : Icons.gps_fixed),
          ),
          SizedBox(height: 16.0),
          FloatingActionButton(
            onPressed: () {
              setState(() {
                _showMgrsGrid = !_showMgrsGrid;
              });
            },
            child: Icon(_showMgrsGrid ? Icons.cancel : Icons.grid_3x3),
          ),
          SizedBox(height: 16.0),
          // FloatingActionButton(
          //   onPressed: () {
          //     // Logic to fetch locations here
          //     fetchLocations();
          //   },
          //   child: Icon(Icons.refresh),
          // ),
          // SizedBox(height: 16.0),
          FloatingActionButton(
            onPressed: _goToUserLocation,
            child: Icon(Icons.my_location),
          ),
          SizedBox(height: 16.0),
          // FloatingActionButton(
          //   onPressed: () {
          //     Get.to(Operationmap());
          //   },
          //   child: Image.asset(
          //     operation,
          //     width: 50,
          //   ),
          // ),
        ],
      ),
    );
  }

  List<Polyline> createMgrsGrid() {
    List<Polyline> gridLines = [];

    double latStart = 10.0;
    double latEnd = 28.0;
    double lonStart = 92.0;
    double lonEnd = 102.0;

    double interval = 0.01; // Set the grid interval as needed
    double latinterval = 0.009; // Set the grid interval as needed

    // Horizontal lines
    for (double lat = latStart - 0.01200; lat <= latEnd; lat += latinterval) {
      gridLines.add(
        Polyline(
          points: [LatLng(lat, lonStart), LatLng(lat, lonEnd)],
          color: ui.Color.fromARGB(136, 45, 182, 216),
          strokeWidth: 1.0,
        ),
      );
    }

    // Vertical lines
    for (double lon = lonStart - 0.00075; lon <= lonEnd; lon += interval) {
      gridLines.add(
        Polyline(
          points: [LatLng(latStart, lon), LatLng(latEnd, lon)],
          color: ui.Color.fromARGB(146, 45, 182, 216),
          strokeWidth: 1.0,
        ),
      );
    }

    return gridLines;
  }

  List<Marker> createGridLabels() {
    List<Marker> labels = [];

    double latStart = 10.0;
    double latEnd = 28.0;
    double lonStart = 92.0;
    double lonEnd = 102.0;

    double interval = 1.0; // Set the interval for the zone center
    double latlngInterval =
        0.10; // Set the interval for the latitude and longitude labels

    for (double lat = latStart - 0.05000;
        lat <= latEnd;
        lat += latlngInterval) {
      for (double lon = lonStart; lon <= lonEnd; lon += latlngInterval) {
        String mgrs = MGRS.latLonToMGRS(lat, lon);
        List<String> mgrsParts = mgrs.split(' ');

        // Extract and truncate the easting and northing parts to 2 digits, with a check
        String easting = mgrsParts[2].length >= 2
            ? mgrsParts[2].substring(0, 2)
            : mgrsParts[2];
        String northing = mgrsParts[3].length >= 2
            ? mgrsParts[3].substring(0, 2)
            : mgrsParts[3];

        // Display easting (longitude numbers) on vertical lines
        labels.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: LatLng(lat, lon),
            builder: (ctx) => Container(
              child: Text(
                '$easting,$northing',
                style: const TextStyle(
                    color: ui.Color.fromARGB(137, 17, 3, 143),
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      }
    }

    // Add zone letter in the center of each zone
    for (double lat = latStart + interval / 2; lat <= latEnd; lat += interval) {
      for (double lon = lonStart + interval / 2;
          lon <= lonEnd;
          lon += interval) {
        labels.add(
          Marker(
            width: 80.0,
            height: 80.0,
            point: LatLng(lat, lon),
            builder: (ctx) => Container(
              child: Text(
                MGRS
                    .latLonToMGRS(lat, lon)
                    .split(' ')[1], // Get the zone letter part
                style: TextStyle(
                    color: ui.Color.fromARGB(150, 0, 0, 0), fontSize: 34),
              ),
            ),
          ),
        );
      }
    }

    return labels;
  }

  // void _addPoint(LatLng point) {
  //   setState(() {
  //     _points.add(point); // Add tapped point to polyline points list
  //     if (_points.length > 1) {
  //       _totalDistance += _calculateDistanceforcustom(_points[_points.length - 2], point); // Calculate distance and add to total
  //     }
  //   });
  // }

//   Offset latLngToScreenPosition(LatLng latLng) {
//   var point = _mapController.latLngToScreenPoint(latLng);
//   if (point != null) {
//     return Offset(point.x.toDouble(), point.y.toDouble());
//   } else {
//     return Offset.zero;
//   }
// }

//   List<Widget> _buildDeleteButtons() {
//     List<Widget> deleteButtons = [];

//     for (var location in _locations) {
//       LatLng latLng = LatLng(location['lat'], location['lng']);
//       Offset position = latLngToScreenPosition(latLng);

//       deleteButtons.add(
//         Positioned(
//           top: position.dy,
//           left: position.dx,
//           child: GestureDetector(
//             onTap: () {
//               print(location);
//             },
//             child: Container(
//               padding: EdgeInsets.all(8.0),
//               decoration: BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.circular(8.0),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.grey.withOpacity(0.5),
//                     spreadRadius: 2,
//                     blurRadius: 5,
//                     offset: Offset(0, 2),
//                   ),
//                 ],
//               ),
//               child: Icon(
//                 Icons.delete,
//                 color: Colors.red,
//               ),
//             ),
//           ),
//         ),
//       );
//     }

//     return deleteButtons;
//   }

  double _calculateDistanceforcustom(LatLng point1, LatLng point2) {
    // Using the Haversine formula to calculate distance between two LatLng points
    const double earthRadius = 6371000; // Radius of the Earth in meters
    double lat1 = point1.latitude * pi / 180;
    double lat2 = point2.latitude * pi / 180;
    double lon1 = point1.longitude * pi / 180;
    double lon2 = point2.longitude * pi / 180;

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    double distance = earthRadius * c;

    return distance;
  }

  void _showOptionsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Container(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ElevatedButton(
                  onPressed: () {
                    _showSaveLocationForm(context); // Show save location form
                  },
                  child: Text('Save'),
                ),
                SizedBox(height: 16.0),
                ElevatedButton(
                  onPressed: () {
                    _calculateDistanceAndBearing();
                    Navigator.pop(context);
                  },
                  child: Text('Calculate'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSaveLocationForm(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String? selectedColor =
            _selectedColor; // Local variable to manage color selection
        return AlertDialog(
          title: Text('Save Location'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller:
                        _searchController, // Use your TextEditingController
                    decoration: InputDecoration(labelText: 'Location Name'),
                  ),
                  SizedBox(height: 16.0),
                  DropdownButtonFormField<String>(
                    value: selectedColor,
                    decoration: InputDecoration(labelText: 'Select Color'),
                    items: <String>['blue', 'red', 'green'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedColor = newValue!;
                      });
                    },
                  ),
                  SizedBox(height: 16.0),
                  ElevatedButton(
                    onPressed: () {
                      _saveLocationDetails(selectedColor, _dotLocation!);
                      Navigator.pop(context); // Close dialog
                    },
                    child: Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _saveLocationDetails(
      String? selectedColor, LatLng locationsave) async {
    String locationName = _searchController.text;

    // Define the URL of the PHP script
    String url = 'http://militarycommand.atwebpages.com/save_location_data.php';

    // Create the POST request
    final response = await http.post(
      Uri.parse(url),
      body: {
        'locationName': locationName,
        'color': selectedColor,
        'lat': locationsave.latitude.toString(),
        'lng': locationsave.longitude.toString(),
      },
    );

    if (response.statusCode == 200) {
      // Handle successful response
      print('Response: ${response.body}');
      fetchLocations();
    } else {
      // Handle error response
      print(
          'Failed to save location details. Status code: ${response.statusCode}');
    }
  }

  void _calculateDistanceAndBearing() {
    if (_currentLocation == null || _dotLocation == null) {
      print('Locations not set.');
      return;
    }

    final distance = _calculatetoDistance(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _dotLocation!.latitude,
      _dotLocation!.longitude,
    );

    final bearing = _calculatetoBearing(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _dotLocation!.latitude,
      _dotLocation!.longitude,
    );

    final bearingInMill = (bearing * (6400 / 360)).toStringAsFixed(2);

    print('အကွာအဝေး: ${distance.toStringAsFixed(2)} km');
    print('ညွှန်းရပ်မေလ်း: $bearingInMill မေလ်း');

    setState(() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'အကွာအဝေး: ${distance.toStringAsFixed(2)} km, ညွှန်းရပ်မေလ်း: $bearingInMill မေလ်း'),
        ),
      );
    });
  }

  double _calculatetoDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // Radius of the Earth in km
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double distance = R * c;

    return distance;
  }

  double _calculatetoBearing(
      double lat1, double lon1, double lat2, double lon2) {
    final double dLon = _toRadians(lon2 - lon1);

    final double y = math.sin(dLon) * math.cos(_toRadians(lat2));
    final double x = math.cos(_toRadians(lat1)) * math.sin(_toRadians(lat2)) -
        math.sin(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.cos(dLon);
    final double bearing = (math.atan2(y, x) * 180.0 / math.pi + 360) % 360;

    return bearing;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  // void _saveLocation() {
  //   print('Location saved!');
  // }

  double _metersToPixels(double meters, double? zoom, double latitude) {
    if (zoom == null) return 0.0;
    double scale = (1 << zoom.toInt()).toDouble();
    double metersPerPixel =
        (156543.03392 * math.cos(latitude * math.pi / 180)) / scale;
    return meters / metersPerPixel;
  }

  void _rotateMapToNorthSouth() {
    _mapController.rotate(_bearing * -1);
  }

  Future<void> _deleteLocationDetails() async {
    String deletelocationName = _deletecontroller.text;

    // Define the URL of the PHP script
    String url =
        'http://militarycommand.atwebpages.com/delete_location_data.php';

    // Create the POST request
    final response = await http.post(
      Uri.parse(url),
      body: {
        'locationName': deletelocationName,
      },
    );
    if (response.statusCode == 200) {
      // Handle successful response
      print('Response: ${response.body}');
      fetchLocations();
    } else {
      // Handle error response
      print(
          'Failed to save location details. Status code: ${response.statusCode}');
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ),
          // ListTile(
          //   leading: Icon(Icons.search),
          //   title: TextField(
          //     controller: _searchController,
          //     decoration: InputDecoration(
          //       hintText: 'Search location',
          //       border: InputBorder.none,
          //     ),
          //     onSubmitted: (value) {
          //       _searchLocation();
          //     },
          //   ),
          //   trailing: ElevatedButton(
          //     onPressed: _searchLocation,
          //     child: Text('Search'),
          //   ),
          // ),
          // ListTile(
          //   leading: Icon(Icons.delete_forever_rounded),
          //   title: TextField(
          //     controller: _deletecontroller,
          //     decoration: InputDecoration(
          //       hintText: 'delete location',
          //       border: InputBorder.none,
          //     ),
          //     onSubmitted: (value) {
          //       _deleteLocationDetails();
          //       Navigator.pop(context);
          //     },
          //   ),
          //   trailing: ElevatedButton(
          //     onPressed: () {
          //       _deleteLocationDetails();
          //       Navigator.pop(context);
          //     },
          //     child: Text('Delete'),
          //   ),
          // ),
          ListTile(
            title: ElevatedButton(
              onPressed: () {
                if (_dotLocation != null) {
                  _addCircle(_dotLocation!, 4600);
                } else {
                  _addCircle(_currentLocation!, 4600);
                }
                Navigator.pop(context); // Close the drawer
              },
              child: Text('MA7'),
            ),
          ),
          ListTile(
            title: ElevatedButton(
              onPressed: () {
                if (_dotLocation != null) {
                  _addCircle(_dotLocation!, 6400);
                } else {
                  _addCircle(_currentLocation!, 6400);
                }
                Navigator.pop(context); // Close the drawer
              },
              child: Text('MA8'),
            ),
          ),
          ListTile(
            title: ElevatedButton(
              onPressed: () {
                if (_dotLocation != null) {
                  _addCircle(_dotLocation!, 12000);
                } else {
                  _addCircle(_currentLocation!, 12000);
                }
                Navigator.pop(context); // Close the drawer
              },
              child: Text('120MM'),
            ),
          ),

          ListTile(
            title: ElevatedButton(
              onPressed: () {
                // Handle 122MM button logic here
              },
              child: Text('122MM'),
            ),
          ),
          ListTile(
            title: ElevatedButton(
              onPressed: () {
                // Handle 155MM button logic here
              },
              child: Text('155MM'),
            ),
          ),
          // ListTile(
          //   title: ElevatedButton(
          //     onPressed: () {
          //       _clearAllTargets(); // Implement a method to clear all target positions
          //       Navigator.pop(context); // Close the drawer
          //     },
          //     child: Text('Clear Targets'),
          //   ),
          // ),

          ListTile(
            title: ElevatedButton(
              onPressed: () {
                _clearAllCircles();

                Navigator.pop(context);
              },
              child: Text('All Clear'),
            ),
          ),
        ],
      ),
    );
  }

  // void _clearAllTargets() {
  //   setState(() {
  //     _points.clear(); // Clear the list of polyline points
  //     _totalDistance = 0.0; // Reset total distance to zero
  //     // Clear any other state variables related to markers or circles if needed

  //   });
  // }

  void _clearAllCircles() {
    setState(() {
      // _points.clear(); // Clear the list of polyline points
      // _totalDistance = 0.0; // Reset total distance to zero
      // Clear any other state variables related to markers or circles if needed
      _circles.clear();
    });
  }

  void _clearAllpollylines() {
    setState(() {
      // Clear the different polylines lists
      _polylines.clear();
      _defensivePolylines.clear();
      _offensivePolylines.clear();
      _attackPolylines.clear();
      _retreatPolylines.clear();
      _boundaryPolylines.clear();
      _finalPerimeterPolylines.clear();
      _defensivePerimeterPolylines.clear();
      _contactPolylines.clear();
      defensiveLines.clear();

      // Remove all markers that use the explosion image
      _markers.removeWhere((marker) {
        // Safely create the widget with a dummy context if necessary
        final widget = marker.builder(
            context); // Replace 'context' with the actual context in use

        // Check if the widget is an Image with the specified asset
        return widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/tdss/explosion.png';
      });
    });
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    Color getColorFromName(String colorName) {
      switch (colorName.toLowerCase()) {
        case 'blue':
          return Colors.blue;
        case 'red':
          return Colors.red;
        case 'green':
          return Colors.green;
        default:
          return Color.fromARGB(255, 13, 214, 147); // Fallback color
      }
    }

    for (var location in _locations) {
      final latitude = double.tryParse(location['latitude']) ?? 0.0;
      final longitude = double.tryParse(location['longitude']) ?? 0.0;
      final point = LatLng(latitude, longitude);
      final label = location['label'] ?? 'Unknown';
      final colorName = location['color'] ?? 'blue';

      markers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: point,
          builder: (ctx) => GestureDetector(
            onTap: () => _showOptionsBottomSheetcustom(context, label),
            child: Container(
              child: Column(
                children: [
                  Icon(
                    Icons.flag,
                    color: getColorFromName(colorName),
                    size: 28.0,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Color.fromARGB(213, 243, 241, 241),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_currentLocation != null) {
      markers.add(
        Marker(
          width: 80.0,
          height: 80.0,
          point: _currentLocation!,
          builder: (ctx) => Container(
            child: Column(
              children: [
                Icon(Icons.location_on, color: Colors.red),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: Text(
                      'My location',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // if (_targetLocation1 != null) {
    //   markers.add(
    //     Marker(
    //       width: 80.0,
    //       height: 80.0,
    //       point: _targetLocation1!,
    //       builder: (ctx) => Icon(Icons.flag, color: Colors.green),
    //     ),
    //   );
    // }

    // if (_targetLocation2 != null) {
    //   markers.add(
    //     Marker(
    //       width: 80.0,
    //       height: 80.0,
    //       point: _targetLocation2!,
    //       builder: (ctx) => Icon(Icons.flag, color: Colors.green),
    //     ),
    //   );
    // }

    return markers;
  }

  List<Polyline> _buildPolylines() {
    if (_currentLocation == null || _dotLocation == null) {
      return [];
    }
    return [
      Polyline(
        points: [_currentLocation!, _dotLocation!],
        strokeWidth: 4.0,
        color: Colors.red,
      ),
    ];
  }

  List<Marker> _buildCircleCenters() {
    List<Marker> markers = [];
    for (var circle in _circles) {
      final latitude = circle['latitude'] ?? 0.0;
      final longitude = circle['longitude'] ?? 0.0;
      final point = LatLng(latitude, longitude);

      markers.add(
        Marker(
          width: 40.0,
          height: 40.0,
          point: point,
          builder: (ctx) => GestureDetector(
            onTap: () => _showRemoveCircleDialog(point),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40.0,
                  height: 40.0,
                  child: Icon(
                    Icons.circle,
                    color: Colors.blue,
                    size: 16.0,
                  ),
                ),
                Positioned(
                  child: Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 24.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<CircleMarker> _buildCircles() {
    List<CircleMarker> circleMarkers = [];
    for (var circle in _circles) {
      final latitude = circle['latitude'] ?? 0.0;
      final longitude = circle['longitude'] ?? 0.0;
      final radius = circle['radius'] ?? 100.0;

      final circleMarker = CircleMarker(
        point: LatLng(latitude, longitude),
        radius: _metersToPixels(radius, _mapController.zoom, latitude),
        color: Colors.blue.withOpacity(0.0),
        borderStrokeWidth: 2,
        borderColor: ui.Color.fromARGB(255, 182, 0, 24),
      );

      circleMarkers.add(circleMarker);
    }
    return circleMarkers;
  }

  void _showRemoveCircleDialog(LatLng point) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove Circle"),
        content: Text("Do you want to remove this circle?"),
        actions: <Widget>[
          TextButton(
            child: Text("Cancel"),
            onPressed: () {
              Navigator.of(ctx).pop();
            },
          ),
          TextButton(
            child: Text("Remove"),
            onPressed: () {
              _removeCircle(point);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }

  void _addCircle(LatLng location, double radius) {
    setState(() {
      _circles.add({
        'latitude': location.latitude,
        'longitude': location.longitude,
        'radius': radius,
      });
    });
  }

  void _removeCircle(LatLng location) {
    setState(() {
      _circles.removeWhere((circle) =>
          circle['latitude'] == location.latitude &&
          circle['longitude'] == location.longitude);
    });
  }

  Future<void> _getUserLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _updateMGRS(_currentLocation!);
      });
    } catch (e) {
      print('Error getting user location: $e');
    }
  }

  void _goToUserLocation() async {
    await _getUserLocation();
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, _zoom);
    }
  }

  // void _toggleMapType() {
  //   setState(() {
  //     if (_mapType == 'openstreetmap') {
  //       _mapType = 'google';
  //     } else {
  //       _mapType = 'openstreetmap';
  //     }
  //   });
  // }

  String _getMapTypeUrl() {
    if (_isOnline) {
      // return 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
      return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    } else {
      return 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}';
    }
  }

  void _searchLocation() {
    String searchLabel = _searchController.text.toLowerCase();
    Map<String, dynamic> location = _locations.firstWhere(
      (location) => location['label'].toString().toLowerCase() == searchLabel,
      orElse: () => {}, // Provide an empty map as default value
    );

    if (location.isNotEmpty) {
      LatLng searchedLocation = LatLng(
        double.parse(location['latitude']),
        double.parse(location['longitude']),
      );
      setState(() {
        _mapController.move(searchedLocation, 17);
        _dotLocation = searchedLocation;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location not found'),
        ),
      );
    }
  }

  void _updateMGRS(LatLng location) {
    _mgrsString =
        MGRS.latLonToMGRS(location.latitude, location.longitude).toString();
    setState(() {});
  }

  void _showOptionsBottomSheetcustom(BuildContext context, label) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: new Icon(Icons.add),
              title: new Text('Add Circle'),
              onTap: () {
                setState(() {
                  _drawCircle = true;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: new Icon(Icons.remove),
              title: new Text('Remove Circle'),
              onTap: () {
                setState(() {
                  _drawCircle = false;
                });
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkConnectivity() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    setState(() {
      _isOnline = connectivityResult != ConnectivityResult.none;
    });

    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }
}

class MGRS {
  static String latLonToMGRS(double lat, double lon) {
    if (lat < -80) return 'Too far South';
    if (lat > 84) return 'Too far North';

    int zoneNumber = 1 + ((lon + 180) / 6).floor();
    double centralMeridian = zoneNumber * 6 - 183;
    double latRad = lat * (pi / 180);
    double lonRad = lon * (pi / 180);
    double centralMeridianRad = centralMeridian * (pi / 180);
    double cosLat = cos(latRad);
    double sinLat = sin(latRad);
    double tanLat = tan(latRad);
    double tanLat2 = tanLat * tanLat;
    double tanLat4 = tanLat2 * tanLat2;
    double tanLat6 = tanLat2 * tanLat4;

    double o = 0.006739496819936062 * cosLat * cosLat;
    double p = 40680631590769 / (6356752.314 * sqrt(1 + o));
    double t = lonRad - centralMeridianRad;

    double aa = p * cosLat * t +
        (p / 6.0 * pow(cosLat, 3) * (1.0 - tanLat2 + o) * pow(t, 3)) +
        (p /
            120.0 *
            pow(cosLat, 5) *
            (5.0 - 18.0 * tanLat2 + tanLat4 + 14.0 * o - 58.0 * tanLat2 * o) *
            pow(t, 5)) +
        (p /
            5040.0 *
            pow(cosLat, 7) *
            (61.0 - 479.0 * tanLat2 + 179.0 * tanLat4 - tanLat6) *
            pow(t, 7));
    double ab = 6367449.14570093 *
            (latRad -
                (0.00251882794504 * sin(2 * latRad)) +
                (0.00000264354112 * sin(4 * latRad)) -
                (0.00000000345262 * sin(6 * latRad)) +
                (0.000000000004892 * sin(8 * latRad))) +
        (tanLat / 2.0 * p * cosLat * cosLat * t * t) +
        (tanLat /
            24.0 *
            p *
            pow(cosLat, 4) *
            (5.0 - tanLat2 + 9.0 * o + 4.0 * o * o) *
            pow(t, 4)) +
        (tanLat /
            720.0 *
            p *
            pow(cosLat, 6) *
            (61.0 -
                58.0 * tanLat2 +
                tanLat4 +
                270.0 * o -
                330.0 * tanLat2 * o) *
            pow(t, 6)) +
        (tanLat /
            40320.0 *
            p *
            pow(cosLat, 8) *
            (1385.0 - 3111.0 * tanLat2 + 543.0 * tanLat4 - tanLat6) *
            pow(t, 8));

    aa = aa * 0.9996 + 500000.0;
    ab = ab * 0.9996;
    if (ab < 0.0) ab += 10000000.0;

    String zoneLetter = 'CDEFGHJKLMNPQRSTUVWXX'
        .substring((lat / 8 + 10).floor(), (lat / 8 + 10).floor() + 1);
    int e100kIndex = (aa ~/ 100000);
    String e100kLetter = [
      'ABCDEFGH',
      'JKLMNPQR',
      'STUVWXYZ'
    ][(zoneNumber - 1) % 3][e100kIndex - 1];
    int n100kIndex = (ab ~/ 100000) % 20;
    String n100kLetter = [
      'ABCDEFGHJKLMNPQRSTUV',
      'FGHJKLMNPQRSTUVABCDE'
    ][(zoneNumber - 1) % 2][n100kIndex];

    String easting = ((aa % 100000).floor()).toString().padLeft(5, '0');
    easting = (int.parse(easting) + 350).toString();
    String northing = ((ab % 100000).floor()).toString().padLeft(5, '0');
    northing = (int.parse(northing) - 350).toString();

    return '$zoneNumber$zoneLetter $e100kLetter$n100kLetter $easting $northing';
  }
}

class MGRSGRID {
  static final List<String> zoneLetters = [
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'J',
    'K',
    'L',
    'M',
    'N',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X'
  ];

  static final List<String> e100kLetters = ['ABCDEFGH', 'JKLMNPQR', 'STUVWXYZ'];

  static final List<String> n100kLetters = [
    'ABCDEFGHJKLMNPQRSTUV',
    'FGHJKLMNPQRSTUVABCDE'
  ];

  static String latLonToMGRS(double lat, double lon) {
    if (lat < -80) return 'Too far South';
    if (lat > 84) return 'Too far North';

    int zoneNumber = ((lon + 180) / 6).floor() + 1;
    double e = zoneNumber * 6 - 183;
    double latRad = lat * (pi / 180);
    double lonRad = lon * (pi / 180);
    double centralMeridianRad = e * (pi / 180);
    double cosLat = cos(latRad);
    double sinLat = sin(latRad);
    double tanLat = tan(latRad);
    double tanLat2 = tanLat * tanLat;
    double tanLat4 = tanLat2 * tanLat2;

    double N = 6378137.0 / sqrt(1 - 0.00669438 * sinLat * sinLat);
    double T = tanLat2;
    double C = 0.006739496819936062 * cosLat * cosLat;
    double A = cosLat * (lonRad - centralMeridianRad);
    double M = 6367449.14570093 *
        (latRad -
            (0.00251882794504 * sin(2 * latRad)) +
            (0.00000264354112 * sin(4 * latRad)) -
            (0.00000000345262 * sin(6 * latRad)) +
            (0.000000000004892 * sin(8 * latRad)));

    double x = (A +
            (1 - T + C) * A * A * A / 6 +
            (5 - 18 * T + T * T + 72 * C - 58 * 0.006739496819936062) *
                A *
                A *
                A *
                A *
                A /
                120) *
        N;
    double y = (M +
            N *
                tanLat *
                (A * A / 2 +
                    (5 - T + 9 * C + 4 * C * C) * A * A * A * A / 24 +
                    (61 -
                            58 * T +
                            T * T +
                            600 * C -
                            330 * 0.006739496819936062) *
                        A *
                        A *
                        A *
                        A *
                        A *
                        A /
                        720)) *
        0.9996;

    x = x * 0.9996 + 500000.0;
    y = y * 0.9996;
    if (y < 0.0) {
      y += 10000000.0;
    }

    String zoneLetter = zoneLetters[((lat + 80) / 8).floor()];
    int e100kIndex = ((x / 100000).floor() % 8);
    int n100kIndex = ((y / 100000).floor() % 20);

    String e100kLetter = e100kLetters[(zoneNumber - 1) % 3][e100kIndex];
    String n100kLetter = n100kLetters[(zoneNumber - 1) % 2][n100kIndex];

    String easting = x.round().toString().substring(1).padLeft(1, '0');
    String northing = y.round().toString().substring(2).padLeft(2, '0');

    return '$easting $northing';
  }
}

class OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(Coords coords, TileLayer options) {
    return TileImageProvider(coords, options);
  }
}

class TileImageProvider extends ImageProvider<TileImageProvider> {
  final Coords coords;
  final TileLayer options;

  TileImageProvider(this.coords, this.options);

  ImageStreamCompleter load(
      TileImageProvider key, ImageDecoderCallback decode) {
    final streamController = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _fetchAndDecode(key, decode, streamController),
      chunkEvents: streamController.stream,
      scale: 1.0,
    );
  }

  Future<ui.Codec> _fetchAndDecode(
      TileImageProvider key,
      ImageDecoderCallback decode,
      StreamController<ImageChunkEvent> streamController) async {
    final file = await _getLocalTile(key.coords, key.options);
    final bytes = await file.readAsBytes();
    return decode(Uint8List.fromList(bytes) as ui.ImmutableBuffer);
  }

  @override
  Future<TileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<TileImageProvider>(this);
  }

  Future<File> _getLocalTile(Coords<num> coords, TileLayer options) async {
    final directory = Directory.systemTemp;
    final filePath = path.join(
        directory.path,
        'tiles',
        options.urlTemplate!.replaceAll(RegExp(r'[/:{}]'), '_'),
        '${coords.z}',
        '${coords.x}',
        '${coords.y}.png');
    final file = File(filePath);

    if (await file.exists()) {
      return file;
    } else {
      return await _downloadAndSaveTile(coords, options, file);
    }
  }

  Future<File> _downloadAndSaveTile(
      Coords<num> coords, TileLayer options, File file) async {
    final url = options.urlTemplate!
        .replaceFirst('{s}', 'a')
        .replaceFirst('{z}', coords.z.toString())
        .replaceFirst('{x}', coords.x.toString())
        .replaceFirst('{y}', coords.y.toString());

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await file.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      // Handle errors such as failed host lookup
      print('Error downloading tile: $e');
    }

    return file;
  }
}

class AssetTileProvider extends TileProvider {
  @override
  ImageProvider getImage(Coords coordinates, TileLayer options) {
    final tilePath =
        'assets/maptiles/${coordinates.z.toInt()}/${coordinates.x.toInt()}/${coordinates.y.toInt()}.png';
    return AssetImage(tilePath);
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
