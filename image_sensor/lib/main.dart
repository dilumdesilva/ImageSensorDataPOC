import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
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

  String imagePath = '';
  String imageName = '';
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

      // Capture sensor values at the point of clicking the picture
      final List<double> initialGyroscopeValues = List.from(gyroscopeValues);
      final List<double> initialAccelerometerValues =
          List.from(accelerometerValues);

      final DateTime now = DateTime.now();
      final String formattedDate = DateFormat('MM-dd-HH-mm').format(now);
      imageName = formattedDate;
      final String imageNameWithExtension = '$formattedDate.jpg';

      final Directory directory = await getApplicationDocumentsDirectory();
      imagePath = '${directory.path}/$imageNameWithExtension';
      await File(image.path).copy(imagePath);

      // Show loader with blur effect
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Stack(
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
              const Center(
                child: CircularProgressIndicator(),
              ),
            ],
          );
        },
      );

      // Arrays to store sensor values over 200 milliseconds
      final List<List<double>> delayedGyroscopeValues = [];
      final List<List<double>> delayedAccelerometerValues = [];

      // Capture sensor values for 200 milliseconds
      const int duration = 200;
      const int interval = 5;
      for (int i = 0; i < duration; i += interval) {
        delayedGyroscopeValues.add(List.from(gyroscopeValues));
        delayedAccelerometerValues.add(List.from(accelerometerValues));
        await Future.delayed(const Duration(milliseconds: interval));
      }

      // Close the loader dialog
      Navigator.of(context).pop();

      // Navigate to the details screen with the captured values
      _naviateToDetailsScreen(
        delayedAccelerometerValues,
        delayedGyroscopeValues,
        initialAccelerometerValues,
        initialGyroscopeValues,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error taking picture: $e');
      }
    }
  }

  void _naviateToDetailsScreen(
    List<List<double>> delayedAccelerometerValues,
    List<List<double>> delayedGyroscopeValues,
    List<double> initialAccelerometerValues,
    List<double> initialGyroscopeValues,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DisplayPictureScreen(
          image: File(imagePath),
          imageName: imageName,
          delayedAccelerometerValues: delayedAccelerometerValues,
          delayedGyroscopeValues: delayedGyroscopeValues,
          initialAccelerometerValues: initialAccelerometerValues,
          initialGyroscopeValues: initialGyroscopeValues,
          luxValue: luxValue,
          deviceModel: deviceModel,
          uniqueID: uniqueID,
        ),
      ),
    );
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
        child: const Icon(Icons.camera_alt),
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
  final List<List<double>> delayedAccelerometerValues;
  final List<List<double>> delayedGyroscopeValues;
  final List<double> initialAccelerometerValues;
  final List<double> initialGyroscopeValues;
  final String deviceModel;
  final String uniqueID;
  final num luxValue;

  const DisplayPictureScreen({
    super.key,
    required this.image,
    required this.imageName,
    required this.delayedAccelerometerValues,
    required this.delayedGyroscopeValues,
    required this.initialAccelerometerValues,
    required this.initialGyroscopeValues,
    required this.deviceModel,
    required this.uniqueID,
    required this.luxValue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Details')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
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
                  'Captured sensor values at the time of taking the picture',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 30),
              Text('Accelerometer: $initialAccelerometerValues'),
              const SizedBox(height: 4),
              Text('Gyroscope: $initialGyroscopeValues'),
              const SizedBox(height: 20),
              Text('Lux value: $luxValue'),
              Text('Device Model: $deviceModel'),
              Text('Unique ID: $uniqueID'),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    saveData(context);
                  },
                  child: const Text('Save Data to a File'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void saveData(BuildContext context) async {
    await GallerySaver.saveImage(image.path, albumName: 'SpectrePoC');
    await _createPdf();
    await _createTextFile();

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Data Saved'),
          content: const Text(
              'Data has been saved to PDF and TXT file successfully.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
            ),
            TextButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(context).pop(); // Dismiss the dialog
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _createTextFile() async {
    final directory = await _getDirectory();
    if (directory == null) {
      print('Unable to get directory');
      return;
    }

    final String dataFilePath = '${directory.path}/spectre_poc/$imageName.txt';
    final File file = File(dataFilePath);

    // Check if the directory exists; if not, create it
    final Directory textDirectory = file.parent;
    if (!await textDirectory.exists()) {
      await textDirectory.create(recursive: true);
    }

    // Open the file for writing
    final IOSink sink = file.openWrite();

    // Write the initial information
    sink.writeln('imageName: $imageName');
    sink.writeln('luxValue: $luxValue');
    sink.writeln('deviceModel: $deviceModel');
    sink.writeln('uniqueID: $uniqueID');
    sink.writeln(); // New line

    // Write the header
    sink.writeln('time,a1,a2,a3,g1,g2,g3');

    // Write the initial sensor values
    sink.writeln(
        '0,${initialAccelerometerValues[0]},${initialAccelerometerValues[1]},${initialAccelerometerValues[2]},${initialGyroscopeValues[0]},${initialGyroscopeValues[1]},${initialGyroscopeValues[2]}');

    // Write the delayed sensor values
    for (int i = 0; i < delayedAccelerometerValues.length; i++) {
      final time = (i + 1) * 5; // Assuming 10 milliseconds interval
      sink.writeln(
          '$time,${delayedAccelerometerValues[i][0]},${delayedAccelerometerValues[i][1]},${delayedAccelerometerValues[i][2]},${delayedGyroscopeValues[i][0]},${delayedGyroscopeValues[i][1]},${delayedGyroscopeValues[i][2]}');
    }

    // Close the file
    await sink.close();
    print('Text file saved to $dataFilePath');
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
    // final imageToSave = pw.MemoryImage(imageBytes);

    // Function to add a page with content
    void addPageContent(pw.Document pdf, int startIndex, int endIndex) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // pw.Image(imageToSave),
                pw.Text(
                  'Image name: $imageName',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 20),
                ),
                pw.Text('-----------------------------------------------'),
                pw.SizedBox(height: 20),
                pw.Text('Lux value: $luxValue'),
                pw.Text('Device Model: $deviceModel'),
                pw.Text('Unique ID: $uniqueID'),
                pw.SizedBox(height: 20),

                pw.Text(
                  'Sensor values at the time of taking the picture',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Accelerometer: $initialAccelerometerValues'),
                pw.SizedBox(height: 4),
                pw.Text('Gyroscope: $initialGyroscopeValues'),
                pw.SizedBox(height: 20),

                pw.Text('Sensor values during the delay of 200 milliseconds',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                for (int i = startIndex; i < endIndex; i++)
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Time: ${i * 5} milliseconds'),
                      pw.Text(
                          'Accelerometer: ${delayedAccelerometerValues[i]}'),
                      pw.Text('Gyroscope: ${delayedGyroscopeValues[i]}'),
                      pw.SizedBox(height: 8),
                    ],
                  ),

                pw.SizedBox(height: 20),
              ],
            );
          },
        ),
      );
    }

    // Determine the number of pages needed
    const int itemsPerPage = 10; // Adjust this value based on your layout
    int totalItems = delayedAccelerometerValues.length;
    int totalPages = (totalItems / itemsPerPage).ceil();

    // Add pages with content
    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      int startIndex = pageIndex * itemsPerPage;
      int endIndex = startIndex + itemsPerPage;
      if (endIndex > totalItems) {
        endIndex = totalItems;
      }
      addPageContent(pdf, startIndex, endIndex);
    }

    // Write or append to the PDF file
    try {
      await file.writeAsBytes(await pdf.save(), mode: FileMode.writeOnly);
      print('PDF saved to $dataFilePath');
    } catch (e) {
      print('Error writing PDF to file: $e');
    }
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
