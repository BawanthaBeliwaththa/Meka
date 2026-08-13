// MEKA V3 Chassis - 3D Printable Head
// Designed for ESP32-CAM/S3, 1602 LCD, INMP441 Mic, MAX98357A Speaker, and Servo mount

$fn = 60; // Smoothness

// Parameters
width = 100;
depth = 60;
height = 80;
wall_thickness = 3;

lcd_width = 72;
lcd_height = 25;

camera_hole_d = 10;
mic_hole_d = 5;
speaker_grill_d = 3;

module meka_head() {
    difference() {
        // Main Box (Outer)
        minkowski() {
            cube([width - 4, depth - 4, height - 4], center=true);
            cylinder(r=2, h=2, center=true);
        }
        
        // Main Box (Inner - hollow out)
        cube([width - wall_thickness*2, depth - wall_thickness*2, height - wall_thickness*2], center=true);

        // Front Face (LCD Cutout - Eyes)
        translate([0, depth/2, 5])
            cube([lcd_width, wall_thickness*4, lcd_height], center=true);
            
        // Front Face (Camera Cutout - Forehead)
        translate([0, depth/2, height/2 - 12])
            rotate([90, 0, 0])
            cylinder(d=camera_hole_d, h=wall_thickness*4, center=true);

        // Bottom Face (Microphone Cutout - Chin)
        translate([0, 0, -height/2])
            cylinder(d=mic_hole_d, h=wall_thickness*4, center=true);
            
        // Bottom Face (Servo Mount Cutout)
        translate([0, -10, -height/2])
            cube([12, 23, wall_thickness*4], center=true); // SG90 servo dimensions

        // Left Face (Speaker Grill)
        for(y = [-10:5:10]) {
            for(z = [-10:5:10]) {
                translate([-width/2, y, z])
                    rotate([0, 90, 0])
                    cylinder(d=speaker_grill_d, h=wall_thickness*4, center=true);
            }
        }
        
        // Right Face (USB Cable Cutout for ESP32)
        translate([width/2, 0, -height/2 + 10])
            cube([wall_thickness*4, 12, 8], center=true);
    }
    
    // Internal Mounting Pegs for LCD
    translate([-lcd_width/2 - 4, depth/2 - wall_thickness - 2, 5 - lcd_height/2 - 4])
        cylinder(d=3, h=4);
    translate([lcd_width/2 + 4, depth/2 - wall_thickness - 2, 5 - lcd_height/2 - 4])
        cylinder(d=3, h=4);
}

// Render the head
meka_head();
