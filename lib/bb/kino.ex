# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino do
  @moduledoc """
  Livebook widgets for the Beam Bots robotics framework.

  This library provides interactive Kino widgets for working with BB robots
  in Livebook notebooks.

  ## Smart Cell

  The easiest way to get started is using the "Manage robot" Smart Cell:

  1. Click "+ Smart" in Livebook
  2. Select "Manage robot"
  3. Enter your robot module name
  4. Evaluate the cell

  This gives you a complete dashboard with all widgets in a grid layout.

  ## Available Widgets

  - `BB.Kino.Safety` - Display and control robot arming state
  - `BB.Kino.JointControl` - Control joint positions with live feedback
  - `BB.Kino.EventStream` - Live stream of robot messages
  - `BB.Kino.Command` - Execute robot commands with forms
  - `BB.Kino.Visualisation` - Interactive 3D robot visualisation

  ## Quick Start

      # Display safety controls
      BB.Kino.safety(MyRobot)

      # Control joints (only works when armed)
      BB.Kino.joints(MyRobot)

      # Watch all robot messages
      BB.Kino.events(MyRobot)

      # Execute commands
      BB.Kino.commands(MyRobot)

      # 3D visualisation with live position updates
      BB.Kino.visualisation(MyRobot)

  ## Usage with Real Robots

  Make sure your robot supervisor is started before creating widgets:

      {:ok, _pid} = MyRobot.start_link()

      BB.Kino.safety(MyRobot)
  """

  @doc """
  Creates a safety status widget for the robot.

  Shows the current arming state and provides arm/disarm controls.

  ## Example

      BB.Kino.safety(MyRobot)
  """
  @spec safety(module()) :: Kino.JS.Live.t()
  defdelegate safety(robot_module), to: BB.Kino.Safety, as: :new

  @doc """
  Creates a joint control widget for the robot.

  Displays all movable joints with position sliders.
  Controls are disabled when the robot is not armed.

  ## Example

      BB.Kino.joints(MyRobot)
  """
  @spec joints(module()) :: Kino.JS.Live.t()
  defdelegate joints(robot_module), to: BB.Kino.JointControl, as: :new

  @doc """
  Creates an event stream widget for the robot.

  Shows a live stream of BB messages with filtering and pause/resume.

  ## Options

  - `:path_filter` - filter by path (e.g., `[:sensor]`)
  - `:message_types` - filter by message types
  - `:max_messages` - max messages to display (default: 100)

  ## Examples

      # All messages
      BB.Kino.events(MyRobot)

      # Only sensor messages
      BB.Kino.events(MyRobot, path_filter: [:sensor])
  """
  @spec events(module(), keyword()) :: Kino.JS.Live.t()
  defdelegate events(robot_module, opts \\ []), to: BB.Kino.EventStream, as: :new

  @doc """
  Creates a command widget for the robot.

  Displays available commands in tabs with dynamic forms for arguments.

  ## Example

      BB.Kino.commands(MyRobot)
  """
  @spec commands(module()) :: Kino.JS.Live.t()
  defdelegate commands(robot_module), to: BB.Kino.Command, as: :new

  @doc """
  Creates a 3D visualisation widget for the robot.

  Displays an interactive Three.js view with real-time joint position updates.
  Supports orbit camera controls (pan, zoom, rotate).

  ## Example

      BB.Kino.visualisation(MyRobot)
  """
  @spec visualisation(module()) :: Kino.JS.Live.t()
  defdelegate visualisation(robot_module), to: BB.Kino.Visualisation, as: :new
end
