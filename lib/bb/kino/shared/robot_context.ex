# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Shared.RobotContext do
  @moduledoc """
  Shared utilities for robot validation and initial state fetching.

  Used by all BB.Kino widgets to validate robot modules and fetch
  initial state data.
  """

  alias BB.Robot.Runtime, as: RobotRuntime

  @doc """
  Validates that the given module is a BB robot.

  Returns `{:ok, robot_module}` if valid, or `{:error, reason}` if not.
  """
  @spec validate_robot(module()) :: {:ok, module()} | {:error, String.t()}
  def validate_robot(robot_module) when is_atom(robot_module) do
    if function_exported?(robot_module, :robot, 0) do
      {:ok, robot_module}
    else
      {:error, "#{inspect(robot_module)} is not a BB robot module"}
    end
  end

  def validate_robot(other) do
    {:error, "Expected a robot module atom, got: #{inspect(other)}"}
  end

  @doc """
  Fetches the initial state for a robot.

  Returns a map containing:
  - `:robot_struct` - the robot topology struct
  - `:positions` - current joint positions
  - `:velocities` - current joint velocities
  - `:state` - runtime state (:disarmed, :idle, :executing, :error, :disarming)
  - `:armed` - boolean indicating if robot is armed
  """
  @spec fetch_initial_state(module()) :: map()
  def fetch_initial_state(robot_module) do
    %{
      robot_struct: RobotRuntime.get_robot(robot_module),
      positions: RobotRuntime.configurations(robot_module),
      velocities: RobotRuntime.velocities(robot_module),
      state: RobotRuntime.state(robot_module),
      armed: BB.Safety.armed?(robot_module)
    }
  end

  @doc """
  Fetches just the safety-related state for a robot.

  Returns a map containing:
  - `:state` - safety state (:disarmed, :armed, :disarming, :error)
  - `:armed` - boolean
  - `:in_error` - boolean
  """
  @spec fetch_safety_state(module()) :: map()
  def fetch_safety_state(robot_module) do
    %{
      state: BB.Safety.state(robot_module),
      armed: BB.Safety.armed?(robot_module),
      in_error: BB.Safety.in_error?(robot_module)
    }
  end
end
