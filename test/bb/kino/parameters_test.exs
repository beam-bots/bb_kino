# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.ParametersTest do
  use ExUnit.Case

  import BB.Unit
  import Kino.Test

  alias BB.Kino.Parameters
  alias BB.Kino.Test.ParameterRobot
  alias BB.Parameter

  setup :configure_livebook_bridge

  setup do
    start_supervised!(ParameterRobot)
    :ok
  end

  describe "the connect payload" do
    test "is JSON-encodable" do
      assert {:ok, _json} = Jason.encode(motion_params())
    end

    test "sends a bounded unit parameter as a magnitude with numeric bounds" do
      trim = motion_params()["motion.trim"]

      assert trim.type == "unit:degree"
      assert trim.value == 0
      assert trim.min == -30
      assert trim.max == 30
    end

    test "sends an unbounded unit parameter as a magnitude" do
      reach = motion_params()["motion.reach"]

      assert reach.type == "unit:meter"
      assert reach.value == 0.5
      assert reach.min == nil
      assert reach.max == nil
    end

    test "converts a value stored in a compatible unit into the declared unit" do
      :ok = Parameter.set(ParameterRobot, [:motion, :trim], ~u(0.26 radian))

      trim = motion_params()["motion.trim"]

      assert trim.type == "unit:degree"
      assert_in_delta trim.value, 14.897, 0.001
      assert trim.min == -30
      assert trim.max == 30
    end

    test "leaves a plain float parameter alone" do
      gain = motion_params()["motion.gain"]

      assert gain.type == "float"
      assert gain.value == 0.5
      assert gain.min == 0.0
      assert gain.max == 1.0
    end
  end

  describe "setting a parameter" do
    test "stores a unit-typed parameter as a unit and broadcasts its magnitude" do
      kino = Parameters.new(ParameterRobot)
      connect(kino)

      push_event(kino, "set_parameter", %{"path" => ["motion", "trim"], "value" => 15})

      assert_broadcast_event(kino, "parameter_changed", %{path: ["motion", "trim"], value: 15.0})
      assert Parameter.get(ParameterRobot, [:motion, :trim]) == {:ok, ~u(15.0 degree)}
    end

    test "broadcasts a compatible unit in the declared unit" do
      kino = Parameters.new(ParameterRobot)
      connect(kino)

      :ok = Parameter.set(ParameterRobot, [:motion, :trim], ~u(0.26 radian))

      assert_broadcast_event(kino, "parameter_changed", %{path: ["motion", "trim"], value: value})
      assert_in_delta value, 14.897, 0.001
    end

    test "reports a unit value outside the declared bounds as an error" do
      kino = Parameters.new(ParameterRobot)
      connect(kino)

      push_event(kino, "set_parameter", %{"path" => ["motion", "trim"], "value" => 45})

      assert_broadcast_event(kino, "error", %{path: ["motion", "trim"]})
      assert Parameter.get(ParameterRobot, [:motion, :trim]) == {:ok, ~u(0 degree)}
    end
  end

  defp motion_params do
    ParameterRobot
    |> Parameters.new()
    |> connect()
    |> Map.fetch!(:parameters)
    |> Map.fetch!("motion")
  end
end
