import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(CarRemoteApp());
}

class CarRemoteApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Car Remote',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Arial',
      ),
      home: CarController(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CarController extends StatefulWidget {
  @override
  _CarControllerState createState() => _CarControllerState();
}

class _CarControllerState extends State<CarController> {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  bool isConnected = false;
  bool isConnecting = false;
  bool isHunting = false;
  String statusMessage = "Disconnected";
  String speedLevel = "Normal";
  String connectButtonText = "Connect";
  StreamSubscription<BluetoothConnectionState>? connectionSubscription;

  // MAC Address input controller
  TextEditingController macAddressController = TextEditingController();

  // Default MAC address for your HC-05
  String defaultMacAddress = "3C:A5:08:0B:3D:DD";

  @override
  void initState() {
    super.initState();
    macAddressController.text = defaultMacAddress; // Pre-fill with your MAC address
    initializeBluetooth();
  }

  Future<void> initializeBluetooth() async {
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Check if Bluetooth is supported and enabled
    if (await FlutterBluePlus.isSupported == false) {
      setState(() {
        statusMessage = "Bluetooth not supported";
      });
      return;
    }

    // Turn on Bluetooth if off
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        setState(() {
          statusMessage = "Please enable Bluetooth manually";
        });
      }
    }
  }

  Future<void> connectToMacAddress(String macAddress) async {
    if (macAddress.isEmpty || !isValidMacAddress(macAddress)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Invalid MAC Address"),
          content: Text("Please enter a valid MAC address in format: XX:XX:XX:XX:XX:XX"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      isConnecting = true;
      connectButtonText = "Connecting...";
      statusMessage = "Connecting to $macAddress";
    });

    try {
      // Create BluetoothDevice from MAC address
      BluetoothDevice device = BluetoothDevice(remoteId: DeviceIdentifier(macAddress));

      // Connect to the device
      await device.connect(timeout: Duration(seconds: 15));

      setState(() {
        connectedDevice = device;
        isConnected = true;
        isConnecting = false;
        statusMessage = "Connected";
        connectButtonText = "Disconnect";
      });

      // Listen for connection state changes
      connectionSubscription = device.connectionState.listen((state) {
        print("Connection state: $state");
        if (state == BluetoothConnectionState.disconnected) {
          if (mounted) {
            setState(() {
              isConnected = false;
              connectedDevice = null;
              writeCharacteristic = null;
              statusMessage = "Disconnected";
              connectButtonText = "Connect";
              isHunting = false;
            });
          }
        }
      });

      // Discover services and find the characteristic for writing
      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
            print("Found write characteristic: ${characteristic.uuid}");
            break;
          }
        }
        if (writeCharacteristic != null) break;
      }

      if (writeCharacteristic == null) {
        print("Warning: No write characteristic found");
      }

    } catch (e) {
      print("Connection failed: $e");
      setState(() {
        isConnecting = false;
        statusMessage = "Connection Failed";
        connectButtonText = "Connect";
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Connection Failed"),
          content: Text("Could not connect to $macAddress\n\nMake sure:\n• HC-05 is powered on\n• Not connected to another device\n• Within range\n• MAC address is correct\n\nError: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  bool isValidMacAddress(String macAddress) {
    // Check if MAC address format is valid (XX:XX:XX:XX:XX:XX)
    RegExp macRegex = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return macRegex.hasMatch(macAddress);
  }

  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        print("Disconnect error: $e");
      }
    }

    connectionSubscription?.cancel();

    setState(() {
      connectedDevice = null;
      writeCharacteristic = null;
      isConnected = false;
      isConnecting = false;
      statusMessage = "Disconnected";
      connectButtonText = "Connect";
      isHunting = false;
    });
  }

  void handleConnectButton() {
    if (isConnecting) return;

    if (isConnected) {
      disconnectDevice();
    } else {
      String macAddress = macAddressController.text.trim().toUpperCase();
      connectToMacAddress(macAddress);
    }
  }

  Future<void> sendCommand(String command) async {
    if (writeCharacteristic != null && isConnected) {
      try {
        List<int> bytes = utf8.encode(command);
        await writeCharacteristic!.write(bytes, withoutResponse: false);
        print("Sent: $command");
      } catch (e) {
        print("Error sending command: $e");
        // Try with writeWithoutResponse
        try {
          List<int> bytes = utf8.encode(command);
          await writeCharacteristic!.write(bytes, withoutResponse: true);
          print("Sent (without response): $command");
        } catch (e2) {
          print("Error sending command (both methods): $e2");
          setState(() {
            statusMessage = "Send Error";
          });
        }
      }
    } else {
      print("Not connected - cannot send command: $command");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Not connected to device")),
      );
    }
  }

  void handleSpeedButton(String speed, String command) {
    setState(() {
      speedLevel = speed;
    });
    sendCommand(command);
  }

  void toggleHunting() {
    setState(() {
      isHunting = !isHunting;
    });

    if (isHunting) {
      sendCommand("T"); // Start line tracking
    } else {
      sendCommand("S"); // Stop
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Car Remote',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 4,
      ),
      backgroundColor: Colors.yellow,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              // MAC Address Input Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      "HC-05 MAC Address",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 8),
                    TextField(
                      controller: macAddressController,
                      decoration: InputDecoration(
                        hintText: "XX:XX:XX:XX:XX:XX",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        fillColor: Colors.white,
                        filled: true,
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                      enabled: !isConnected, // Disable when connected
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Status Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      "Status: $statusMessage",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Speed: $speedLevel",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Mode: ${isHunting ? 'Hunting' : 'Manual'}",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Connect Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isConnecting ? null : handleConnectButton,
                  child: Text(
                    connectButtonText,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    disabledBackgroundColor: Colors.purple.withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 4,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Movement Controls
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Forward button
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: GestureDetector(
                        onTapDown: isConnected ? (_) => sendCommand("F") : null,
                        onTapUp: isConnected ? (_) => sendCommand("S") : null,
                        onTapCancel: isConnected ? () => sendCommand("S") : null,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: isConnected ? Colors.cyan : Colors.grey,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "FWD",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 15),

                    // Left, Back, Right row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: GestureDetector(
                            onTapDown: isConnected ? (_) => sendCommand("L") : null,
                            onTapUp: isConnected ? (_) => sendCommand("S") : null,
                            onTapCancel: isConnected ? () => sendCommand("S") : null,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.cyan : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  "LEFT",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: GestureDetector(
                            onTapDown: isConnected ? (_) => sendCommand("B") : null,
                            onTapUp: isConnected ? (_) => sendCommand("S") : null,
                            onTapCancel: isConnected ? () => sendCommand("S") : null,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.cyan : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  "BCK",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: GestureDetector(
                            onTapDown: isConnected ? (_) => sendCommand("R") : null,
                            onTapUp: isConnected ? (_) => sendCommand("S") : null,
                            onTapCancel: isConnected ? () => sendCommand("S") : null,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: isConnected ? Colors.cyan : Colors.grey,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  "RIGHT",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 20),

              // Speed Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SizedBox(
                    width: 90,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: isConnected
                          ? () => handleSpeedButton("Slow", "X")
                          : null,
                      child: Text(
                        "SLOW",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: isConnected
                          ? () => handleSpeedButton("Normal", "Y")
                          : null,
                      child: Text(
                        "NORMAL",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: isConnected
                          ? () => handleSpeedButton("Fast", "Z")
                          : null,
                      child: Text(
                        "FAST",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 30),

              // Hunt Toggle Button
              SizedBox(
                width: 200,
                height: 50,
                child: ElevatedButton(
                  onPressed: isConnected ? toggleHunting : null,
                  child: Text(
                    isHunting ? "STOP HUNTING" : "START HUNTING",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    disabledBackgroundColor: Colors.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 6,
                  ),
                ),
              ),

              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    connectionSubscription?.cancel();
    connectedDevice?.disconnect();
    macAddressController.dispose();
    super.dispose();
  }
}