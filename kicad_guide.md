# Translating Meka to KiCad

Wokwi uses its own `diagram.json` format which cannot be directly opened by KiCad. To design your PCB, you will need to re-draw the schematic in KiCad using its vast library of real-world footprints.

Here is your exact blueprint to perfectly translate your Wokwi simulation into a professional KiCad PCB!

## Step 1: Create the Project
1. Open **KiCad**.
2. Click **File > New Project...**
3. Save it in your `Meka` folder and name it `Meka_PCB`.
4. Open the **Schematic Editor** (`Meka_PCB.kicad_sch`).

## Step 2: Bill of Materials (BOM)
Press `A` on your keyboard in the Schematic Editor to open the **Symbol Chooser**. Search for and place the following symbols:

| Component            | KiCad Symbol Search Term          | Notes                                                                                            |
| :---------------------| :----------------------------------| :-------------------------------------------------------------------------------------------------|
| **ESP32 DevKit**     | `ESP32-WROOM-32` or `NodeMCU-32S` | You can also use a generic `Conn_02x15_Counter_Clockwise` for standard 30-pin DevKit footprints. |
| **OLED Display**     | `Conn_01x04`                      | A simple 4-pin female header is best since you will plug the OLED module into the PCB.           |
| **DHT22 Sensor**     | `DHT22`                           | Typically a 4-pin device, though only 3 are used.                                                |
| **Servo Motor**      | `Conn_01x03`                      | A 3-pin male header for the servo wire.                                                          |
| **NeoPixel Strip**   | `Conn_01x03`                      | A 3-pin header (5V, Data, GND).                                                                  |
| **Buzzer**           | `Buzzer`                          | A standard passive piezo buzzer.                                                                 |
| **Potentiometer**    | `R_Potentiometer`                 | standard 3-pin rotary potentiometer.                                                             |
| **8x LEDs**          | `LED`                             | Standard 3mm or 5mm Red LEDs.                                                                    |
| **1x 10kΩ Resistor** | `R`                               | Pull-up for the DHT22.                                                                           |
| **1x 330Ω Resistor** | `R`                               | Protection resistor for the NeoPixel data line.                                                  |

## Step 3: Wiring Connections
Press `W` to draw wires between the components. Follow this exact connection map which mirrors your Wokwi setup:

### Core I2C (OLED Screen)
* **ESP32 Pin 21** ➔ OLED `SDA`
* **ESP32 Pin 22** ➔ OLED `SCL`
* **ESP32 3V3** ➔ OLED `VCC`
* **ESP32 GND** ➔ OLED `GND`

### Sensors & Actuators
* **ESP32 Pin 4** ➔ DHT22 `DATA` *(Also connect a 10k resistor between DHT `DATA` and `3V3`)*
* **ESP32 Pin 15** ➔ Buzzer Positive `+` (Buzzer `-` to `GND`)
* **ESP32 Pin 18** ➔ Servo `PWM` pin
* **ESP32 Pin 34** ➔ Potentiometer middle `SIG` pin (Outer pins to `3V3` and `GND`)
* **ESP32 Pin 13** ➔ 330Ω Resistor ➔ NeoPixel `DIN` (Data In)

### LED Array
Connect the Anode (`+`, long leg) of each LED to the ESP32, and the Cathode (`-`, flat side) to `GND`. 
> [!TIP]
> In real life, you **must** add a current-limiting resistor (e.g., 220Ω or 330Ω) in series with every single LED to prevent them from burning out! Wokwi simulates this automatically, but physical PCBs require real resistors.

* **ESP32 Pin 26** ➔ LED 1
* **ESP32 Pin 27** ➔ LED 2
* **ESP32 Pin 14** ➔ LED 3
* **ESP32 Pin 12** ➔ LED 4
* **ESP32 Pin 25** ➔ LED 5
* **ESP32 Pin 33** ➔ LED 6
* **ESP32 Pin 32** ➔ LED 7
* **ESP32 Pin 19** ➔ LED 8

## Next Steps
Once you wire the schematic, you will run the **Footprint Assignment Tool** to choose physical sizes (like `0805` for surface mount resistors or `THT` for through-hole), and then you can click the green **Open PCB in board editor** button to start routing your copper traces!
