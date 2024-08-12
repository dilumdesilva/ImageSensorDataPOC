import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_sensor/lux_sensor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:light_sensor/light_sensor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

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

  const MyHomePage({super.key, required this.camera});

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
    accelerometerEventStream().listen((AccelerometerEvent event) {
      setState(() {
        accelerometerValues = [event.x, event.y, event.z];
      });
    });

    gyroscopeEventStream().listen((GyroscopeEvent event) {
      setState(() {
        gyroscopeValues = [event.x, event.y, event.z];
      });
    });

    // Initialize Lux sensor and get value (implement as per your platform requirements)
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
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      setState(() {
        deviceModel = androidInfo.model;
        uniqueID = androidInfo.id ?? uuid.v4();
      });
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      setState(() {
        deviceModel = iosInfo.utsname.machine;
        uniqueID = iosInfo.identifierForVendor ?? uuid.v4();
      });
    }
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;

      final image = await _controller.takePicture();
      final DateTime now = DateTime.now();
      final String formattedDate = DateFormat('MM-dd-HH-mm').format(now);
      final String imageName = formattedDate;
      final String imageNameWithExtension = '$formattedDate.jpg';

      final Directory directory = await getApplicationDocumentsDirectory();
      final String imagePath = '${directory.path}/$imageNameWithExtension';
      await File(image.path).copy(imagePath);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayPictureScreen(
            image: File(imagePath),
            imageName: imageName,
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
            return SizedBox(
                width: size.width,
                height: size.height,
                child: CameraPreview(_controller));
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class DisplayPictureScreen extends StatelessWidget {
  final File image;
  final String imageName;
  final List<double> accelerometerValues;
  final List<double> gyroscopeValues;
  final String deviceModel;
  final String uniqueID;
  final num luxValue;

  const DisplayPictureScreen({
    super.key,
    required this.image,
    required this.imageName,
    required this.accelerometerValues,
    required this.gyroscopeValues,
    required this.deviceModel,
    required this.uniqueID,
    required this.luxValue,
  });

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
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  saveData();
                },
                child: const Text('Save Data to a File'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void saveData() async {
    await GallerySaver.saveImage(image.path, albumName: 'SpectrePoC');
    await _createPdf();
    await _createTextFile();
  }

  Future<void> _createPdf() async {
    final pdf = pw.Document();
    final directory = await _getDirectory();
    if (directory == null) {
      print('Unable to get directory');
      return;
    }

    final String dataFilePath = '${directory.path}/spectre_poc/$imageName.pdf';
    final File file = File(dataFilePath);

    // Check if the directory exists; if not, create it
    final Directory pdfDirectory = File(dataFilePath).parent;
    if (!await pdfDirectory.exists()) {
      await pdfDirectory.create(recursive: true);
    }

    // Load the image from file (Make sure to provide the correct path)
    final imageFile = image;
    final imageBytes = imageFile.readAsBytesSync();
    final imageToSave = pw.MemoryImage(imageBytes);

    // Add content to the PDF
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // pw.Image(imageToSave),
              pw.Text(imageName),
              pw.Text('Accelerometer: $accelerometerValues'),
              pw.Text('Gyroscope: $gyroscopeValues'),
              pw.Text('Lux value: $luxValue'),
              pw.Text('Device Model: $deviceModel'),
              pw.Text('Unique ID: $uniqueID'),
            ],
          );
        },
      ),
    );

    // Write or append to the PDF file
    try {
      await file.writeAsBytes(await pdf.save(), mode: FileMode.writeOnly);
      print('PDF saved to $dataFilePath');
    } catch (e) {
      print('Error writing PDF to file: $e');
    }
  }

  Future<void> _createTextFile() async {
    final directory = await _getDirectory();
    if (directory == null) {
      print('Unable to get directory');
      return;
    }

    final String dataFilePath = '${directory.path}/spectre_poc/image_data.txt';
    final File file = File(dataFilePath);

    // Check if the directory exists; if not, create it
    final Directory textDirectory = file.parent;
    if (!await textDirectory.exists()) {
      await textDirectory.create(recursive: true);
    }

    final String sensorData = '''
    $imageName
    Accelerometer: $accelerometerValues
    Gyroscope: $gyroscopeValues
    Lux value: $luxValue
    Device Model: $deviceModel
    Unique ID: $uniqueID

    ''';

    // Write or append to the text file
    if (await file.exists()) {
      // File exists, append to it
      await file.writeAsString(sensorData, mode: FileMode.append);
    } else {
      // File does not exist, create and write
      await file.writeAsString(sensorData);
    }

    print('Text file saved to $dataFilePath');
  }

  Future<Directory?> _getDirectory() async {
    if (Platform.isAndroid) {
      // For Android, use getExternalFilesDir() to get app-specific storage directory
      return await getExternalStorageDirectory();
    } else if (Platform.isIOS) {
      // For iOS, use getApplicationDocumentsDirectory() for app-specific storage
      return await getApplicationDocumentsDirectory();
    } else {
      return null;
    }
  }
}
