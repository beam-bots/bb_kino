# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.CommandTest do
  use ExUnit.Case

  import Kino.Test

  alias BB.Kino.Command
  alias BB.Kino.Test.CommandRobot

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

    # The command never returns on its own, so neither a result nor an error is
    # broadcast while it runs — proving the widget no longer expects it to.
    refute_receive {:runtime_broadcast, "js_live", ^ref, {:event, "result", _, _}}, 100
    refute_receive {:runtime_broadcast, "js_live", ^ref, {:event, "error", _, _}}, 50

    push_event(kino, "cancel", %{})
    assert_broadcast_event(kino, "error", %{command: "run_forever", error: ":cancelled"})
  end
end
