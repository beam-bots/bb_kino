# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.CommandTest do
  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.Command
  alias BB.Kino.Test.CommandRobot
  alias BB.Robot.Runtime

  setup :configure_livebook_bridge

  setup do
    start_supervised!(CommandRobot)
    :ok
  end

  test "a continuous command keeps running until cancelled" do
    kino = Command.new(CommandRobot)
    ref = kino.ref
    connect(kino)

    push_event(kino, "execute", %{"command" => "run_forever", "args" => %{}})
    assert_broadcast_event(kino, "executing", %{command: "run_forever"})

    assert_broadcast_event(
      kino,
      "running_changed",
      %{running: [%{name: "run_forever", execution_id: execution_id}]},
      1_000
    )

    # The command never returns on its own, so neither a result nor an error is
    # broadcast while it runs — proving the widget no longer expects it to.
    :sys.get_state(kino.pid)
    refute_received {:runtime_broadcast, "js_live", ^ref, {:event, "result", _, _}}
    refute_received {:runtime_broadcast, "js_live", ^ref, {:event, "error", _, _}}

    push_event(kino, "cancel", %{"execution_id" => execution_id})
    assert_broadcast_event(kino, "error", %{command: "run_forever", error: ":cancelled"})
  end

  test "cancels a command the widget did not start" do
    kino = Command.new(CommandRobot)
    connect(kino)

    # Started by something else entirely — the widget never sees the pid.
    {:ok, cmd} = Runtime.execute(CommandRobot, :run_forever, %{})
    ref = Process.monitor(cmd)

    assert_broadcast_event(kino, "running_changed", %{
      running: [%{name: "run_forever", execution_id: execution_id}]
    })

    push_event(kino, "cancel", %{"execution_id" => execution_id})

    assert_receive {:DOWN, ^ref, :process, ^cmd, {:shutdown, :cancelled}}, 1000
  end
end
