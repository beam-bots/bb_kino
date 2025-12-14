# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Shared.PubSubHandler do
  @moduledoc """
  Common patterns for subscribing and unsubscribing from BB PubSub.

  Used by widgets that need to receive real-time updates from robots.
  """

  @doc """
  Subscribes to one or more paths on a robot's PubSub.

  ## Options

  - `:message_types` - list of message type modules to filter by

  ## Examples

      subscribe(MyRobot, [[:sensor], [:actuator]])
      subscribe(MyRobot, [[:sensor, :joint1]], message_types: [BB.Message.Sensor.JointState])
  """
  @spec subscribe(module(), [[atom()]], keyword()) :: :ok
  def subscribe(robot, paths, opts \\ []) do
    message_types = Keyword.get(opts, :message_types, [])

    Enum.each(paths, fn path ->
      if message_types == [] do
        BB.subscribe(robot, path)
      else
        BB.subscribe(robot, path, message_types: message_types)
      end
    end)

    :ok
  end

  @doc """
  Unsubscribes from one or more paths on a robot's PubSub.
  """
  @spec unsubscribe(module(), [[atom()]]) :: :ok
  def unsubscribe(robot, paths) do
    Enum.each(paths, fn path ->
      BB.unsubscribe(robot, path)
    end)

    :ok
  end

  @doc """
  Subscribes to state machine transitions.

  State transitions are published to `[:state_machine]` and contain
  `from` and `to` states.
  """
  @spec subscribe_state_machine(module()) :: :ok
  def subscribe_state_machine(robot) do
    BB.subscribe(robot, [:state_machine])
    :ok
  end

  @doc """
  Subscribes to all sensor messages.
  """
  @spec subscribe_sensors(module(), keyword()) :: :ok
  def subscribe_sensors(robot, opts \\ []) do
    subscribe(robot, [[:sensor]], opts)
  end

  @doc """
  Subscribes to all actuator messages.
  """
  @spec subscribe_actuators(module(), keyword()) :: :ok
  def subscribe_actuators(robot, opts \\ []) do
    subscribe(robot, [[:actuator]], opts)
  end
end
