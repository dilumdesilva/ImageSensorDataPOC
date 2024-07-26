import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_sensor/utils.dart';
import 'package:light_sensor/light_sensor.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:flutter/services.dart';

import 'lux_sensor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(camera: camera),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final CameraDescription camera;

  const MyHomePage({Key? key, required this.camera}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  List<double> accelerometerValues = [0, 0, 0];
  List<double> gyroscopeValues = [0, 0, 0];
  double luxValue = 0;
  String deviceModel = '';
  String uniqueID = '';

  static const platform = MethodChannel('com.example.your_app/android_id');

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
    );

    _initializeControllerFuture = _controller.initialize();

    initializeSensors();
  }

  Future<void> initializeSensors() async {
    accelerometerEvents.listen((AccelerometerEvent event) {
      setState(() {
        accelerometerValues = [event.x, event.y, event.z];
      });
    });

    gyroscopeEvents.listen((GyroscopeEvent event) {
      setState(() {
        gyroscopeValues = [event.x, event.y, event.z];
      });
    });

    if (Platform.isAndroid) {
      final bool hasSensor = await LightSensor.hasSensor();
      if (!hasSensor) {
        print('Light sensor is not available');
        return;
      }

      LightSensor.luxStream().listen((event) {
        luxValue = event.toDouble();
      });
    }

    if (Platform.isIOS) {
      double? lux = await LuxSensor.getLuxValue();
      setState(() {
        luxValue = lux ?? 0.0;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _getDeviceInfo();
  }

  Future<void> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    var uuid = const Uuid();
    if (Theme.of(context).platform == TargetPlatform.android) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      setState(() {
        deviceModel = androidInfo.model!;
      });

      uniqueID = androidInfo.id ?? uuid.v4();
      print('Android ID: $uniqueID');
      // uniqueID = await _getAndroidId() ?? uuid.v4();
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      setState(() {
        deviceModel = iosInfo.utsname.machine!;
        uniqueID = iosInfo.identifierForVendor ?? uuid.v4();
      });
    }
  }

  Future<String?> _getAndroidId() async {
    try {
      final String result = await platform.invokeMethod('getAndroidId');
      return result;
    } on PlatformException catch (e) {
      print("Failed to get Android ID: '${e.message}'.");
      return null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _takePicture() async {
    try {
      await _initializeControllerFuture;

      final image = await _controller.takePicture();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(
            image: File(image.path),
            accelerometerValues: accelerometerValues,
            gyroscopeValues: gyroscopeValues,
            luxValue: luxValue,
            deviceModel: deviceModel,
            uniqueID: uniqueID,
          ),
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Picture'),
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final size = MediaQuery.of(context).size;
            return Container(
                width: size.width,
                height: size.height,
                color:
                    isPortraitMode(context) ? Colors.transparent : Colors.black,
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: Stack(
                    fit: isPortraitMode(context)
                        ? StackFit.expand
                        : StackFit.loose,
                    children: [
                      isPortraitMode(context)
                          ? CameraPreview(_controller)
                          : Align(
                              alignment: AlignmentDirectional.center,
                              child: CameraPreview(_controller),
                            ),
                      // _buildCaptureButton(),
                    ],
                  ),
                ));
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: const Icon(Icons.camera),
      ),
    );
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final File image;
  final List<double> accelerometerValues;
  final List<double> gyroscopeValues;
  final String deviceModel;
  final String uniqueID;
  final num luxValue;

  const DisplayPictureScreen({
    Key? key,
    required this.image,
    required this.accelerometerValues,
    required this.gyroscopeValues,
    required this.deviceModel,
    required this.uniqueID,
    required this.luxValue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 350,
                height: 350,
                child: Image.file(image, fit: BoxFit.fitWidth),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                  'Captured sensor values at the time of taking the picture'),
            ),
            const SizedBox(height: 30),
            Text('Accelerometer: $accelerometerValues'),
            Text('Gyroscope: $gyroscopeValues'),
            Text('Lux value: $luxValue'),
            Text('Device Model: $deviceModel'),
            Text('Unique ID: $uniqueID'),
          ],
        ),
      ),
    );
  }
}
