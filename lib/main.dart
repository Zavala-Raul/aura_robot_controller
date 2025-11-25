import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'robot_service.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
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
  Completer<GoogleMapController> _mapController = Completer();
  
  LatLng _currentPos = LatLng(20.076829, -98.769919); 
  Set<Marker> _markers = {};
  bool _gpsInicializado = false;

  // CORRECCIÓN 1: El Timer ahora vive aquí arriba, no en los botones
  Timer? _timerSimulacion; 

  List<BluetoothDiscoveryResult> _devices = [];
  bool _isScanning = false;
  bool _modoBrazo = false; 

  @override
  void initState() {
    super.initState();
    _inicializarTodo();
  }

  // CORRECCIÓN 2: Limpiar el timer si cierras la app para no dejar fugas
  @override
  void dispose() {
    _timerSimulacion?.cancel();
    super.dispose();
  }

  Future<void> _inicializarTodo() async {
    await _requestPermissions();
    await _obtenerUbicacionReal();
    _actualizarMarcador();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth, 
      Permission.bluetoothScan, 
      Permission.bluetoothConnect, 
      Permission.location
    ].request();
  }

  Future<void> _obtenerUbicacionReal() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      setState(() {
        _currentPos = LatLng(position.latitude, position.longitude);
        _gpsInicializado = true;
      });
      final GoogleMapController controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentPos, zoom: 20)
      ));
    } catch (e) {
      print("Error GPS: $e");
    }
  }

  void _actualizarMarcador() {
    setState(() {
      _markers = {
        Marker(
          markerId: MarkerId('aura_robot'),
          position: _currentPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: "AURA UGV", snippet: "Enlace Activo"),
          anchor: Offset(0.5, 0.5),
        )
      };
    });
  }

  void _simularMovimientoMapa(String direccion) {
    // Velocidad: ~30 cm/segundo
    double microPaso = 0.0000003; 

    double lat = _currentPos.latitude;
    double lng = _currentPos.longitude;

    setState(() {
      switch (direccion) {
        case 'F': lat += microPaso; break;
        case 'B': lat -= microPaso; break;
        case 'L': lng -= microPaso; break;
        case 'R': lng += microPaso; break;
      }
      _currentPos = LatLng(lat, lng);
      _actualizarMarcador();
    });
  }

  // CORRECCIÓN 3: Función centralizada para detener todo
  void _detenerTodo() {
    _robot.setMoveCommand('S'); // Parar Arduino
    _timerSimulacion?.cancel(); // Parar Mapa
    _timerSimulacion = null;    // Limpiar variable
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_robot.isConnected ? "AURA: ONLINE 🟢" : "OFFLINE 🔴"),
        backgroundColor: Colors.black87,
        actions: [
          if (_robot.isConnected)
            Switch(
              value: _modoBrazo,
              onChanged: (val) {
                _detenerTodo(); // Seguridad al cambiar modo
                setState(() => _modoBrazo = val);
              },
              activeColor: Colors.orange,
            )
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.hybrid,
            initialCameraPosition: CameraPosition(target: _currentPos, zoom: 20),
            markers: _markers,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) _mapController.complete(controller);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
          ),
          if (!_robot.isConnected || _modoBrazo) Container(color: Colors.black54),
          SafeArea(
            child: Column(
              children: [
                if (!_robot.isConnected) _buildPanelConexion(),
                Spacer(),
                if (_robot.isConnected && !_modoBrazo) _buildControlesRuedas(),
                if (_robot.isConnected && _modoBrazo) 
                   Container(
                     decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                     padding: EdgeInsets.only(bottom: 20),
                     child: _buildControlesBrazo()
                   ),
              ],
            ),
          ),
          if (!_gpsInicializado)
            Positioned(
              top: 100, left: 20, right: 20,
              child: Card(color: Colors.yellow, child: Padding(padding: EdgeInsets.all(8), child: Text("🛰️ Calibrando GPS...", textAlign: TextAlign.center, style: TextStyle(color: Colors.black)))),
            )
        ],
      ),
    );
  }

  Widget _buildPanelConexion() {
    return Container(
      margin: EdgeInsets.all(20), padding: EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: () {
               setState(() { _devices.clear(); _isScanning = true; });
               FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
                 setState(() => _devices.add(r));
               }).onDone(() => setState(() => _isScanning = false));
            },
            child: Text(_isScanning ? "Escaneando..." : "BUSCAR AURA"),
          ),
          Container(
            height: 120,
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(_devices[i].device.name ?? "???", style: TextStyle(color: Colors.black)),
                subtitle: Text(_devices[i].device.address, style: TextStyle(color: Colors.grey)),
                trailing: ElevatedButton(child: Text("Link"), onPressed: () async {
                    bool ok = await _robot.connectToDevice(_devices[i].device.address);
                    setState(() {});
                  }),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildControlesRuedas() {
    return Container(
      padding: EdgeInsets.only(bottom: 20, top: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black, Colors.transparent]
        ),
      ),
      child: Column(
        children: [
          _botonFlecha("AVANZAR", Icons.keyboard_arrow_up, 'F', Colors.cyan),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _botonFlecha("IZQ", Icons.keyboard_arrow_left, 'L', Colors.cyan),
              SizedBox(width: 20),
              // BOTÓN STOP MEJORADO
              GestureDetector(
                onTap: _detenerTodo, // Usa la función centralizada
                child: Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.8), shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent, width: 3),
                    boxShadow: [BoxShadow(color: Colors.red, blurRadius: 10)]
                  ),
                  child: Icon(Icons.stop, size: 50, color: Colors.white),
                ),
              ),
              SizedBox(width: 20),
              _botonFlecha("DER", Icons.keyboard_arrow_right, 'R', Colors.cyan),
            ],
          ),
          SizedBox(height: 10),
          _botonFlecha("RETROCEDER", Icons.keyboard_arrow_down, 'B', Colors.cyan),
        ],
      ),
    );
  }

  // CORRECCIÓN 4: Este widget ahora usa el Timer de la CLASE (_timerSimulacion)
  Widget _botonFlecha(String label, IconData icon, String cmd, Color colorBase) {
    return GestureDetector(
      onTapDown: (_) {
        _detenerTodo(); // Seguridad: limpiar cualquier timer previo
        _robot.setMoveCommand(cmd); // Mando físico
        
        // Asignamos el timer a la variable DE LA CLASE
        _timerSimulacion = Timer.periodic(Duration(milliseconds: 100), (t) {
          _simularMovimientoMapa(cmd);
        });
      },
      // Al soltar, cancelamos la variable DE LA CLASE
      onTapUp: (_) => _detenerTodo(),
      onTapCancel: () => _detenerTodo(),
      
      child: Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          color: colorBase.withOpacity(0.2), shape: BoxShape.circle, 
          border: Border.all(color: colorBase, width: 2),
          boxShadow: [BoxShadow(color: colorBase.withOpacity(0.2), blurRadius: 10)]
        ),
        child: Icon(icon, size: 40, color: Colors.white),
      ),
    );
  }

  Widget _buildControlesBrazo() {
    return Column(
      children: [
        Text("MANIPULADOR", style: TextStyle(color: Colors.orange, letterSpacing: 2, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        _sliderBrazo("Base", 'a'),
        _sliderBrazo("Hombro", 'b'),
        _sliderBrazo("Codo", 'c'),
        _sliderBrazo("Gripper", 'f'),
      ],
    );
  }

  Widget _sliderBrazo(String label, String eje) {
    double _val = 90;
    return StatefulBuilder(builder: (ctx, setLocalState) => Padding(
      padding: EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Slider(
              value: _val, min: 0, max: 180, activeColor: Colors.orange,
              onChanged: (v) => setLocalState(() => _val = v),
              onChangeEnd: (v) => _robot.moveArm(eje, v.toInt()),
            ))
        ],
      ),
    ));
  }
}