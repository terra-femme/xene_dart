# Xene Sandbox: Hardware Dial & Feed Transitions

Welcome to the Hardware Dial Sandbox. This folder contains a standalone prototype of the "Mechanical Interaction" system.

## 🛠 Tuning Guide

If you want to change how the dial "feels", look for these variables in `channel_dial.dart`:

1.  **`_snapStrength`**: Controls how aggressively the dial pulls toward a channel tick.
2.  **`_rotationFriction`**: Adjusts how much "weight" the knob has when you spin it.
3.  **`_tickCount`**: Change this to add more channels (e.g., set to 8 for 45-degree ticks).

## 🎓 Educational Deep Dives

This sandbox utilizes three core native Flutter technologies for maximum efficiency:

1.  **Math (`atan2`)**: We use Cartesian-to-Polar coordinate conversion to track circular movement.
2.  **Haptics (`selectionClick`)**: Low-level system calls to the phone's vibration motor for "mechanical" feedback.
3.  **GPU Transitions (`SlideTransition`)**: Affine 2D transforms that move pixels without re-rendering the widget tree.

## 🔍 Debugging

Open the `SandboxPreview` screen in the app. You will see a **Real-Time Debug Overlay** at the top that shows:
- Exact Rotation Angle (0 to 360)
- Current Polar Segment
- Target Snap Angle
- Haptic Trigger Status
