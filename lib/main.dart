import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'robot_service.dart';

void main() {
    runApp(MaterialApp(
    home: RobotControlPage(),
    theme: ThemeData.dark(), 
  ));
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

  bool _modoBrazo = false; // False = Ruedas, True = Brazo

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
      appBar: AppBar(
        title: Text(_robot.isConnected ? "CONECTADO 🟢" : "DESCONECTADO 🔴"),
        actions: [
          // Switch para cambiar entre modo Ruedas y Brazo
          if (_robot.isConnected)
            Switch(
              value: _modoBrazo,
              onChanged: (val) => setState(() => _modoBrazo = val),
              activeColor: Colors.orange,
              activeTrackColor: Colors.deepOrange,
            )
        ],
      ),
      body: Column(
        children: [
          // SECCIÓN 1: CONEXIÓN (Solo visible si no estamos conectados)
          if (!_robot.isConnected) ...[
            ElevatedButton.icon(
              icon: Icon(Icons.search),
              label: Text(_isScanning ? "Escaneando..." : "Buscar HC-06"),
              onPressed: _startScan,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (ctx, i) {
                  final dev = _devices[i].device;
                  return ListTile(
                    title: Text(dev.name ?? "Desconocido"),
                    subtitle: Text(dev.address),
                    trailing: ElevatedButton(
                      child: Text("Conectar"),
                      onPressed: () async {
                        bool exito = await _robot.connectToDevice(dev.address);
                        setState(() {}); 
                        if (exito) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("¡Conexión establecida!")));
                      },
                    ),
                  );
                },
              ),
            ),
          ] 
          // SECCIÓN 2: CONTROLES (Visible al conectar)
          else ...[
            // Botón de desconexión rápido
            Container(
              color: Colors.black12,
              child: ListTile(
                title: Text("Modo: ${_modoBrazo ? 'BRAZO ROBÓTICO 🦾' : 'VEHÍCULO 🏎️'}"),
                trailing: IconButton(
                  icon: Icon(Icons.power_settings_new, color: Colors.red),
                  onPressed: () { _robot.disconnect(); setState(() {}); },
                ),
              ),
            ),
            
            Expanded(
              child: _modoBrazo ? _buildControlesBrazo() : _buildControlesRuedas(),
            ),
          ]
        ],
      ),
    );
  }

  // --- PANTALLA DE RUEDAS ---
  Widget _buildControlesRuedas() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _botonFlecha("ADELANTE", Icons.arrow_upward, 'F'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _botonFlecha("IZQ", Icons.arrow_back, 'L'),
              SizedBox(width: 40), // Espacio central
              _botonFlecha("DER", Icons.arrow_forward, 'R'),
            ],
          ),
          _botonFlecha("ATRÁS", Icons.arrow_downward, 'B'),
        ],
      ),
    );
  }

  Widget _botonFlecha(String label, IconData icon, String cmd) {
    return GestureDetector(
      // AQUÍ ESTÁ LA MAGIA DEL MOVIMIENTO CONTINUO
      onTapDown: (_) => _robot.setMoveCommand(cmd), // Al presionar: Manda 'F' (y el heartbeat lo repite)
      onTapUp: (_) => _robot.setMoveCommand('S'),   // Al soltar: Manda 'S' (y el heartbeat repite Stop)
      onTapCancel: () => _robot.setMoveCommand('S'), // Seguridad extra
      child: Container(
        margin: EdgeInsets.all(10),
        width: 90, height: 90,
        decoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(blurRadius: 10, color: Colors.blue.withOpacity(0.5))]),
        child: Icon(icon, size: 40, color: Colors.white),
      ),
    );
  }

  Widget _buildControlesBrazo() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Text("PRECAUCIÓN: Movimiento directo de servos"),
          SizedBox(height: 20),
          _sliderBrazo("Base (Eje A)", 'a', 0, 180),
          _sliderBrazo("Hombro (Eje B)", 'b', 0, 180),
          _sliderBrazo("Codo (Eje C)", 'c', 0, 180),
          _sliderBrazo("Muñeca V (Eje D)", 'd', 0, 180),
          _sliderBrazo("Muñeca R (Eje E)", 'e', 0, 180),
          _sliderBrazo("Gripper (Eje F)", 'f', 0, 180),
        ],
      ),
    );
  }
  
  Widget _sliderBrazo(String nombre, String eje, double min, double max) {
    // Variable local para visualización (no necesitamos guardarla en estado global)
    double _valorLocal = 90; 
    
    return StatefulBuilder(
      builder: (context, setStateLocal) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("$nombre: ${_valorLocal.toInt()}°"),
            Slider(
              value: _valorLocal,
              min: min, max: max,
              divisions: 180,
              label: _valorLocal.round().toString(),
              activeColor: Colors.orange,
              // IMPORTANTE: Solo enviamos el comando al SOLTAR el slider (onChangeEnd)
              // Si usas onChanged, enviarás 50 comandos por segundo y saturarás el Arduino.
              onChanged: (val) {
                setStateLocal(() => _valorLocal = val);
              },
              onChangeEnd: (val) {
                _robot.moveArm(eje, val.toInt());
                print("Enviando brazo: $eje${val.toInt()}");
              },
            ),
          ],
        );
      },
    );
  }
}