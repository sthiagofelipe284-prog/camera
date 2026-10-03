import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  await initializeBackgroundService();
  runApp(const MyApp());
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartService,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'remote_camera_channel',
      initialNotificationTitle: 'Câmera Remota Ativa',
      initialNotificationContent: 'O streaming está rodando em segundo plano.',
      foregroundServiceTypes: [AndroidForegroundType.camera],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

@pragma('vm:entry-point')
void onStartService(ServiceInstance service) async {
  WakelockPlus.enable();

  CameraController? backgroundController;
  if (cameras.isNotEmpty) {
    backgroundController = CameraController(
      cameras[0], 
      ResolutionPreset.medium, 
      enableAudio: false,
    );
    await backgroundController.initialize();
  }

  final app = Router();

  app.get('/', (shelf.Request request) {
    return shelf.Response.ok(
      '<html><head><meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>Stream Ao Vivo</title></head>'
      '<body style="background:#000;color:#fff;text-align:center;font-family:sans-serif;">'
      '<h2>Câmera Remota Ativa</h2>'
      '<img src="/video" style="max-width:100%;height:auto;border-radius:8px;" />'
      '</body></html>',
      headers: {'content-type': 'text/html'},
    );
  });

  app.get('/video', (shelf.Request request) async {
    final StreamController<List<int>> controller = StreamController<List<int>>();

    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (backgroundController == null || !backgroundController.value.isInitialized) {
        return;
      }
      try {
        XFile imageFile = await backgroundController.takePicture();
        Uint8List bytes = await imageFile.readAsBytes();

        controller.add(
          utf8Bytes('--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${bytes.length}\r\n\r\n') +
          bytes +
          utf8Bytes('\r\n'),
        );
      } catch (e) {}
    });

    return shelf.Response(
      200,
      body: controller.stream,
      headers: {
        'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
        'Connection': 'keep-alive',
        'Content-Type': 'multipart/x-mixed-replace; boundary=frame',
      },
    );
  });

  var server = await shelf_io.serve(app.call, '0.0.0.0', 8080);

  service.on('stopService').listen((event) {
    backgroundController?.dispose();
    server.close(force: true);
    WakelockPlus.disable();
    service.stopSelf();
  });
}

List<int> utf8Bytes(String s) => s.codeUnits;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Câmera Remota',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CameraHomePage(),
    );
  }
}

class CameraHomePage extends StatefulWidget {
  const CameraHomePage({super.key});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage> {
  bool isRunning = false;

  @override
  void initState() {
    super.initState();
    checkPermissions();
  }

  Future<void> checkPermissions() async {
    await [
      Permission.camera,
      Permission.ignoreBatteryOptimizations,
    ].request();
  }

  void toggleService() async {
    final service = FlutterBackgroundService();
    bool isRunningNow = await service.isRunning();

    if (isRunningNow) {
      service.invoke('stopService');
      setState(() => isRunning = false);
    } else {
      await Permission.ignoreBatteryOptimizations.request();
      service.startService();
      setState(() => isRunning = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Câmera Remota - Celular 1')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRunning ? Icons.videocam : Icons.videocam_off,
                size: 80,
                color: isRunning ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 20),
              Text(
                isRunning ? 'Status: Transmitindo ao Vivo' : 'Status: Parado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isRunning ? Colors.green : Colors.red),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: toggleService,
                style: ElevatedButton.styleFrom(backgroundColor: isRunning ? Colors.red : Colors.blue),
                child: Text(
                  isRunning ? 'Parar Transmissão' : 'Iniciar Transmissão',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
