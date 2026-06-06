# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.EventStreamThrottleTest do
  @moduledoc """
  Tests for `BB.Kino.EventStream`'s debounce + flush behaviour.

  Messages are injected straight into the widget's server process so the
  component can be driven in isolation with short intervals; otherwise tests
  would have to wait the full production defaults.
  """

  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.EventStream
  alias BB.Kino.Examples.TestRobot
  alias BB.Message
  alias BB.Message.Sensor.BatteryState
  alias BB.Message.Sensor.JointState

  @flush_interval_ms 20
  @debounce_window_ms 100

  setup :configure_livebook_bridge

  setup do
    start_supervised!(TestRobot)
    :ok
  end

  defp start_widget do
    kino =
      EventStream.new(TestRobot,
        flush_interval_ms: @flush_interval_ms,
        debounce_window_ms: @debounce_window_ms
      )

    connect(kino)
    kino
  end

  defp joint_state_message do
    {:ok, message} =
      Message.new(JointState, :simulated,
        names: [:joint1],
        positions: [0.0],
        velocities: [0.0],
        efforts: [0.0]
      )

    message
  end

  defp battery_state_message do
    {:ok, message} = Message.new(BatteryState, :simulated, voltage: 12.0)
    message
  end

  defp inject(kino, path, message), do: send(kino.pid, {:bb, path, message})

  describe "flush" do
    test "buffers a new message until the flush interval elapses" do
      kino = start_widget()
      ref = kino.ref

      inject(kino, [:sensor, :imu], joint_state_message())

      refute_receive {:runtime_broadcast, "js_live", ^ref, {:event, "messages", _, _}},
                     @flush_interval_ms - 5

      assert_broadcast_event(kino, "messages", %{messages: [_]})
    end

    test "batches multiple distinct messages into one render" do
      kino = start_widget()

      inject(kino, [:sensor, :imu], joint_state_message())
      inject(kino, [:sensor, :battery], battery_state_message())

      assert_broadcast_event(kino, "messages", %{messages: [_, _]})
    end

    test "schedules a fresh flush for messages arriving after the previous one fired" do
      kino = start_widget()

      inject(kino, [:sensor, :imu], joint_state_message())
      assert_broadcast_event(kino, "messages", %{messages: [_]})

      inject(kino, [:sensor, :battery], battery_state_message())
      assert_broadcast_event(kino, "messages", %{messages: [_]})
    end
  end

  describe "debounce" do
    test "drops repeats of the same path + payload type within the window" do
      kino = start_widget()

      for _ <- 1..5 do
        inject(kino, [:sensor, :imu], joint_state_message())
      end

      assert_broadcast_event(kino, "messages", %{messages: [_]})
    end

    test "lets different payload types from the same path through" do
      kino = start_widget()

      inject(kino, [:sensor, :imu], joint_state_message())
      inject(kino, [:sensor, :imu], battery_state_message())

      assert_broadcast_event(kino, "messages", %{messages: [_, _]})
    end
  end
end
