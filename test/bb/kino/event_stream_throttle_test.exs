# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.EventStreamThrottleTest do
  @moduledoc """
  Tests for `BB.Kino.EventStream`'s debounce + flush behaviour.

  Messages are injected straight into the widget's server process so the
  component can be driven in isolation. The flush interval and debounce
  window are set far beyond the length of a test, and the test flushes by
  sending the widget `:flush` itself, so no outcome depends on a timer.
  """

  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.EventStream
  alias BB.Kino.Examples.TestRobot
  alias BB.Message
  alias BB.Message.Sensor.BatteryState
  alias BB.Message.Sensor.JointState

  @longer_than_any_test :timer.hours(1)

  setup :configure_livebook_bridge

  setup do
    start_supervised!(TestRobot)
    :ok
  end

  defp start_widget(opts \\ []) do
    kino =
      EventStream.new(
        TestRobot,
        Keyword.merge(
          [
            flush_interval_ms: @longer_than_any_test,
            debounce_window_ms: @longer_than_any_test
          ],
          opts
        )
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

  defp flush_now(kino), do: send(kino.pid, :flush)

  describe "flush" do
    test "buffers a new message until the flush interval elapses" do
      kino = start_widget()
      ref = kino.ref

      inject(kino, [:sensor, :imu], joint_state_message())
      :sys.get_state(kino.pid)

      refute_received {:runtime_broadcast, "js_live", ^ref, {:event, "messages", _, _}}

      flush_now(kino)
      assert_broadcast_event(kino, "messages", %{messages: [_]})
    end

    test "batches multiple distinct messages into one render" do
      kino = start_widget()

      inject(kino, [:sensor, :imu], joint_state_message())
      inject(kino, [:sensor, :battery], battery_state_message())
      flush_now(kino)

      assert_broadcast_event(kino, "messages", %{messages: [_, _]})
    end

    test "schedules a fresh flush for messages arriving after the previous one fired" do
      kino = start_widget(flush_interval_ms: 20)

      inject(kino, [:sensor, :imu], joint_state_message())
      assert_broadcast_event(kino, "messages", %{messages: [_]}, 1_000)

      inject(kino, [:sensor, :battery], battery_state_message())
      assert_broadcast_event(kino, "messages", %{messages: [_]}, 1_000)
    end
  end

  describe "debounce" do
    test "drops repeats of the same path + payload type within the window" do
      kino = start_widget()

      for _ <- 1..5 do
        inject(kino, [:sensor, :imu], joint_state_message())
      end

      flush_now(kino)

      assert_broadcast_event(kino, "messages", %{messages: [_]})
    end

    test "lets different payload types from the same path through" do
      kino = start_widget()

      inject(kino, [:sensor, :imu], joint_state_message())
      inject(kino, [:sensor, :imu], battery_state_message())
      flush_now(kino)

      assert_broadcast_event(kino, "messages", %{messages: [_, _]})
    end
  end
end
