// Meka Smart Node - Alexa-Style Enclosure
// 3D Printable in PLA/PETG
// Units are in mm

$fn = 100; // High resolution for smooth cylinders

// Dimensions
outer_radius = 45;
inner_radius = 42;
height = 100;
wall_thickness = outer_radius - inner_radius;

base_thickness = 3;
esp32_width = 28;
esp32_length = 52;
usb_hole_width = 12;
usb_hole_height = 8;
wire_hole_radius = 5;

// OLED Screen (0.96" SSD1306)
oled_width = 26;
oled_height = 15;

module base() {
    difference() {
        // Main body
        cylinder(h=height, r=outer_radius);
        
        // Hollow inside
        translate([0, 0, base_thickness])
            cylinder(h=height, r=inner_radius);
            
        // Anti-Counterfeit Hidden Watermark (Debossed into inner floor)
        // This makes it virtually impossible to print without the MEKA brand being embedded inside.
        translate([0, 0, base_thickness - 0.6])
            linear_extrude(1)
            text("© 2026 MEKA - ORIGINAL", size=5, font="Orbitron:style=Bold", halign="center", valign="center");
            
        // USB cutout at the bottom (for power)
        translate([outer_radius - 5, -usb_hole_width/2, base_thickness])
            cube([10, usb_hole_width, usb_hole_height]);
            
        // Wire cutout for relay connections
        translate([-outer_radius + 2, 0, base_thickness + 10])
            rotate([0, 90, 0])
            cylinder(h=10, r=wire_hole_radius);
            
        // OLED Screen Cutout (Front face, halfway up)
        translate([0, outer_radius - 5, height/2])
            cube([oled_width, 10, oled_height], center=true);
            
        // Debossed MEKA Official Graphic Logo + Vector Text (Front face, below OLED)
        translate([0, outer_radius + 0.1, 24])
            rotate([90, 0, 0])
            linear_extrude(2) {
                translate([0, 8]) scale([0.9, 0.9]) meka_logo_graphic();
                translate([0, -10]) scale([0.5, 0.5]) vector_text_MEKA();
            }
            
        // Giant Debossed Vector MEKA Text (Back face)
        translate([0, -outer_radius - 0.1, height/2])
            rotate([90, 0, 180])
            linear_extrude(2)
            scale([1.8, 1.8]) vector_text_MEKA();
            
        // Debossed Logo + Text (Left side)
        translate([-outer_radius - 0.1, 0, height/2])
            rotate([0, 0, -90])
            rotate([90, 0, 0])
            linear_extrude(2) {
                translate([0, 6]) scale([0.7, 0.7]) meka_logo_graphic();
                translate([0, -9]) scale([0.4, 0.4]) vector_text_MEKA();
            }
            
        // Debossed Logo + Text (Right side)
        translate([outer_radius + 0.1, 0, height/2])
            rotate([0, 0, 90])
            rotate([90, 0, 0])
            linear_extrude(2) {
                translate([0, 6]) scale([0.7, 0.7]) meka_logo_graphic();
                translate([0, -9]) scale([0.4, 0.4]) vector_text_MEKA();
            }
    }
    
    // ESP32 Standoffs (Mounting pins)
    standoff_height = 10;
    standoff_radius = 3;
    standoff_hole_radius = 1;
    
    // 4 standoffs for ESP32 standard devkit footprint
    translate([-esp32_width/2, -esp32_length/2, base_thickness]) {
        for (x = [2, esp32_width-2]) {
            for (y = [2, esp32_length-2]) {
                translate([x, y, 0])
                difference() {
                    cylinder(h=standoff_height, r=standoff_radius);
                    cylinder(h=standoff_height+1, r=standoff_hole_radius);
                }
            }
        }
    }
    
    // OLED PCB Standoffs (Inner front wall)
    translate([0, inner_radius - 2, height/2]) {
        for(x = [-14, 14]) {
            for(z = [-14, 14]) {
                translate([x, 0, z]) rotate([90, 0, 0])
                cylinder(h=5, r=1.5); // 1.5mm radius peg for M2/M3 screw hole friction fit
            }
        }
    }
}

module top_cap() {
    cap_height = 10;
    
    difference() {
        union() {
            // Cap outer rim
            cylinder(h=cap_height, r=outer_radius);
            // Cap inner lip for snap fit
            translate([0, 0, -5])
                cylinder(h=5, r=inner_radius - 0.5);
        }
        
        // Hollow inner lip
        translate([0, 0, -5.1])
            cylinder(h=15.2, r=inner_radius - 3);
            
        // Speaker / Mic grille holes (Alexa dotted pattern)
        // Skip the innermost ring so we have room for the logo
        for (r = [18 : 8 : 30]) {
            for (a = [0 : 360/(r*1.5) : 360]) {
                rotate([0, 0, a])
                translate([r, 0, -6])
                cylinder(h=20, r=1.5);
            }
        }
        
        // Debossed Graphic Logo on Top Cap
        translate([0, 0, cap_height - 1])
            linear_extrude(2)
            scale([0.8, 0.8, 1])
            meka_logo_graphic();
            
        // Center LED light ring hole
        translate([0, 0, -6])
        cylinder(h=20, r=4);
    }
}

// Display both together (Offset for visualization):
base();
translate([0, 0, height + 15]) top_cap();

// ==========================================
// INSTRUCTIONS FOR EXPORTING TO G-CODE:
// 1. Comment out the block above.
// 2. Uncomment base(); and export as Base.stl
// 3. Uncomment top_cap(); and export as Cap.stl
// 4. Open the STL files in Ultimaker Cura or PrusaSlicer.
// 5. Slice and save the generated .gcode file to your SD Card.
// ==========================================

module draw_line(p1, p2, w) {
    hull() {
        translate(p1) circle(d=w, $fn=16);
        translate(p2) circle(d=w, $fn=16);
    }
}

module meka_logo_graphic() {
    // Circles
    difference() { circle(d=20, $fn=60); circle(d=18.5, $fn=60); }
    difference() { circle(d=16, $fn=60); circle(d=14.5, $fn=60); }
    
    w = 1;
    // M
    draw_line([-4, -4], [-4, 4], w);
    draw_line([4, -4], [4, 4], w);
    draw_line([-4, 4], [0, -1], w);
    draw_line([4, 4], [0, -1], w);
    draw_line([-4, -4], [0, 1], w);
    draw_line([4, -4], [0, 1], w);
}

module vector_text_MEKA() {
    w = 1.2;
    translate([-21.5, -5]) {
        // M
        draw_line([0, 0], [0, 10], w);
        draw_line([10, 0], [10, 10], w);
        draw_line([0, 10], [5, 0], w);
        draw_line([10, 10], [5, 0], w);
        
        // E
        draw_line([14, 0], [14, 10], w);
        draw_line([14, 10], [20, 10], w);
        draw_line([14, 5], [19, 5], w);
        draw_line([14, 0], [20, 0], w);
        
        // K
        draw_line([24, 0], [24, 10], w);
        draw_line([24, 5], [31, 10], w);
        draw_line([24, 5], [31, 0], w);
        
        // A
        draw_line([35, 0], [39, 10], w);
        draw_line([43, 0], [39, 10], w);
        draw_line([36.6, 4], [41.4, 4], w);
    }
}
