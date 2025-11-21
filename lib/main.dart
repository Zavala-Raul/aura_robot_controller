import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'robot_service.dart';

void main() {
  runApp(MaterialApp(home: RobotControlPage()));
}

class RobotControlPage extends StatefulWidget {
  @override
  _RobotControlPageState createState() => _RobotControlPageState();
}

class _RobotControlPageState extends State<RobotControlPage> {
  final RobotService _robot = RobotService();
  
  // Lista de dispositivos encontrados
  List<BluetoothDiscoveryResult> _devices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  // Pedir permisos al iniciar
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // Escanear dispositivos
  void _startScan() {
    setState(() { _devices.clear(); _isScanning = true; });
    FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
      setState(() => _devices.add(r));
    }).onDone(() => setState(() => _isScanning = false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("AURA Control")),
      body: Column(
        children: [
          // SECCIÓN 1: CONEXIÓN
          if (!_robot.isConnected) ...[
            ElevatedButton(onPressed: _startScan, child: Text(_isScanning ? "Escaneando..." : "Buscar Robot")),
            Expanded(
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (ctx, i) {
                  final dev = _devices[i].device;
                  return ListTile(
                    title: Text(dev.name ?? "Sin nombre"),
                    subtitle: Text(dev.address),
                    trailing: ElevatedButton(
                      child: Text("Conectar"),
                      onPressed: () async {
                        bool success = await _robot.connectToDevice(dev.address);
                        setState(() {}); // Refrescar UI
                        if (success) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Conectado!")));
                      },
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            // SECCIÓN 2: CONTROLES (Solo visible si está conectado)
            Container(
              color: Colors.green[100],
              padding: EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("CONECTADO ✅"),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red),
                    onPressed: () { _robot.disconnect(); setState(() {}); },
                  )
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 20),
                    Text("--- MOTORES ---", style: TextStyle(fontWeight: FontWeight.bold)),
                    // Ejemplo de Botón "Adelante"
                    GestureDetector(
                      onTapDown: (_) => _robot.setMoveCommand('F'), // Al presionar
                      onTapUp: (_) => _robot.setMoveCommand('S'),   // Al soltar
                      child: Container(
                        width: 100, height: 100,
                        color: Colors.blue,
                        child: Icon(Icons.arrow_upward, size: 50, color: Colors.white),
                      ),
                    ),
                    // Aquí agregarías los botones de Izq, Der, Atrás igual que arriba...
                    
                    SizedBox(height: 40),
                    Text("--- BRAZO ---", style: TextStyle(fontWeight: FontWeight.bold)),
                    // Slider Base (Eje 'a')
                    Text("Base (Eje A)"),
                    Slider(
                      value: 90, 
                      min: 0, max: 180, 
                      onChanged: (val) {
                        // Solo visual, no enviamos nada aun para no saturar
                      },
                      onChangeEnd: (val) {
                        // Enviamos SOLO cuando suelta el slider
                        _robot.moveArm('a', val.toInt());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}