# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.VisualisationTest do
  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.Test.PlanarRobot
  alias BB.Kino.Visualisation
  alias BB.Math.Transform2D
  alias BB.Message
  alias BB.Message.Sensor.JointState
  alias BB.Robot.Runtime, as: RobotRuntime
  alias BB.Robot.State, as: RobotState

  setup :configure_livebook_bridge

  setup do
    start_supervised!(PlanarRobot)
    :ok
  end

  test "a planar joint's configuration connects as a pose" do
    kino = Visualisation.new(PlanarRobot)

    %{positions: positions} = connect(kino)

    assert positions["shoulder"] == 0.0
    assert pose(positions["ground"]) == {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0}
  end

  test "a planar configuration is lifted through its plane normal" do
    set_ground(Transform2D.new(1.0, 2.0, :math.pi() / 2))

    kino = Visualisation.new(PlanarRobot)

    %{positions: positions} = connect(kino)

    assert pose(positions["ground"]) == {1.0, 2.0, 0.0, 0.0, 0.0, 0.707107, 0.707107}
  end

  test "a planar configuration is a pose when broadcast" do
    kino = Visualisation.new(PlanarRobot)
    connect(kino)

    {:ok, message} =
      Message.new(JointState, :simulated,
        names: [:ground],
        positions: [Transform2D.new(0.5, 0.0, 0.0)]
      )

    BB.publish(PlanarRobot, [:sensor, :simulated], message)

    assert_broadcast_event(kino, "positions_updated", %{positions: positions}, 500)

    assert pose(positions["ground"]) == {0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0}
  end

  defp set_ground(configuration) do
    :ok =
      PlanarRobot
      |> RobotRuntime.get_robot_state()
      |> RobotState.set_configuration(:ground, configuration)
  end

  # Flattened and rounded, so a pose can be compared as a whole without
  # pattern matching on floats.
  defp pose(%{xyz: xyz, quat: quat}) do
    {round6(xyz.x), round6(xyz.y), round6(xyz.z), round6(quat.x), round6(quat.y), round6(quat.z),
     round6(quat.w)}
  end

  defp round6(number), do: Float.round(number, 6)
end
