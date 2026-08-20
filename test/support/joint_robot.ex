# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Test.EffortOnlyActuator do
  @moduledoc """
  A driver that accepts effort commands and nothing else.

  Stands in for a port whose hardware can't be told to go to a position, so
  that the widget's handling of a refused slider command can be exercised.
  """
  use BB.Actuator

  alias BB.Message.Actuator.Command

  @impl BB.Actuator
  def command_payloads(_opts), do: [Command.Effort]

  @impl BB.Actuator
  def disarm(_opts), do: :ok

  @impl BB.Actuator
  def init(opts), do: {:ok, %{bb: Keyword.fetch!(opts, :bb)}}

  @impl BB.Actuator
  def handle_command(_message, state), do: {:noreply, state}
end

defmodule BB.Kino.Test.JointRobot do
  @moduledoc """
  A robot with one driven joint, for exercising the joint control sliders.
  """
  use BB

  settings do
    name(:kino_joint_robot)
  end

  topology do
    link :base_link do
      joint :shoulder do
        type(:revolute)

        limit do
          lower(~u(-90 degree))
          upper(~u(90 degree))
          effort(~u(10 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        actuator(:motor, BB.Kino.Test.EffortOnlyActuator)

        sensor(:motor_position, {BB.Sensor.OpenLoopPositionEstimator, actuator: :motor})

        link(:arm_link)
      end
    end
  end
end
