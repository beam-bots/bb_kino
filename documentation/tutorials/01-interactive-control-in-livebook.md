<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Interactive Control in Livebook

In this tutorial, you'll create an interactive Livebook notebook for controlling and monitoring a Beam Bots robot.

## What We're Building

A Livebook notebook with:
- Safety controls to arm/disarm the robot
- Joint position sliders
- Real-time 3D visualisation
- Event stream monitoring
- Command execution

## Prerequisites

- [Livebook](https://livebook.dev/) installed
- Basic familiarity with Livebook notebooks
- A BB robot module (or use the example in this tutorial)

## Step 1: Create a New Notebook

Open Livebook and create a new notebook. Add a setup cell with dependencies:

```elixir
Mix.install([
  {:bb, "~> 0.12"},
  {:bb_kino, "~> 0.1"}
])
```

## Step 2: Define a Robot

If you don't have a robot module, create a simple one:

```elixir
defmodule DemoRobot do
  use BB

  commands do
    command :arm do
      handler BB.Command.Arm
      allowed_states [:disarmed]
    end

    command :disarm do
      handler BB.Command.Disarm
      allowed_states [:idle]
    end
  end

  topology do
    link :base do
      joint :shoulder, type: :revolute do
        limit lower: ~u(-90 degree), upper: ~u(90 degree), velocity: ~u(60 degree_per_second)
      end

      joint :elbow, type: :revolute do
        limit lower: ~u(-120 degree), upper: ~u(120 degree), velocity: ~u(90 degree_per_second)
      end
    end
  end
end
```

## Step 3: Start the Robot

Start the robot in simulation mode:

```elixir
{:ok, _pid} = BB.Supervisor.start_link(DemoRobot, simulation: :kinematic)
```

## Step 4: Add the Safety Widget

The safety widget shows robot state and provides arm/disarm controls:

```elixir
BB.Kino.safety(DemoRobot)
```

You'll see:
- Current state indicator (Disarmed, Idle, Executing, Error)
- Arm button (enabled when disarmed)
- Disarm button (enabled when idle)

Click **Arm** to enable robot control.

## Step 5: Add Joint Control

Add sliders for controlling joint positions:

```elixir
BB.Kino.joints(DemoRobot)
```

With the robot armed, drag the sliders to move joints. The sliders:
- Respect joint limits from the DSL
- Show current position in degrees
- Send commands via `BB.Actuator.set_position/4`
- Are disabled when the robot is disarmed

## Step 6: Add 3D Visualisation

See the robot in 3D:

```elixir
BB.Kino.visualisation(DemoRobot)
```

The visualisation:
- Renders links and joints from the topology
- Updates in real-time as joints move
- Supports orbit controls (drag to rotate, scroll to zoom)

## Step 7: Add Event Stream

Monitor PubSub messages in real-time:

```elixir
BB.Kino.events(DemoRobot)
```

Features:
- Filter by path (e.g., `sensor.shoulder`)
- Pause/resume
- Expandable message details
- Automatic scrolling

## Step 8: Add Commands

Execute robot commands through forms:

```elixir
BB.Kino.commands(DemoRobot)
```

Commands defined in the DSL appear as tabs with auto-generated forms. Fill in arguments and click execute.

## Using the Manage Robot Smart Cell

For a unified dashboard, use the smart cell:

1. Click **+ Smart** in your notebook
2. Select **Manage robot**
3. Enter your robot module name
4. Check which widgets to display
5. Evaluate the cell

The smart cell generates code that combines all selected widgets in a grid layout.

## Combined Widget Layouts

Create custom layouts using `Kino.Layout`:

```elixir
Kino.Layout.grid([
  Kino.Layout.grid([
    BB.Kino.safety(DemoRobot),
    BB.Kino.joints(DemoRobot)
  ], columns: 1),
  BB.Kino.visualisation(DemoRobot)
], columns: 2)
```

See [Create Combined Widget Layout](../how-to/create-combined-widget-layout.md) for more layout options.

## Controlling Real Hardware

For real hardware:

1. Remove the `:simulation` option when starting
2. Ensure hardware drivers are properly configured
3. The widgets work identically

```elixir
# Real hardware
{:ok, _} = BB.Supervisor.start_link(MyRealRobot)

# Same widgets
BB.Kino.safety(MyRealRobot)
BB.Kino.joints(MyRealRobot)
```

## Understanding Widget Behaviour

### Safety Widget

- Subscribes to `[:state_machine]` and `[:safety]` channels
- Updates state display in real-time
- Buttons are state-aware (arm only when disarmed, etc.)

### Joint Widget

- Reads joint definitions from robot struct
- Sliders use joint limits
- Position updates come from sensor messages
- Disabled when robot is not armed

### Visualisation Widget

- Builds Three.js model from topology
- Receives position updates via Kino channels
- Supports standard orbit controls

### Event Widget

- Subscribes to all robot messages
- Buffers recent messages for display
- Filter applies to message paths

### Command Widget

- Generates forms from command DSL definitions
- Validates argument types
- Shows command results inline

## Troubleshooting

### Widget not updating

Check that:
- The robot is started
- You're using the correct robot module
- Livebook cell is connected

### Sliders disabled

The robot must be armed. Click the Arm button in the safety widget.

### Visualisation blank

Ensure:
- WebGL is enabled in your browser
- The robot has a topology with links

## Next Steps

- [Create Combined Widget Layout](../how-to/create-combined-widget-layout.md) - Advanced layout techniques
- Connect to real hardware
- Add custom widgets for your specific robot
