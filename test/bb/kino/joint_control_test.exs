# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.JointControlTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Kino.Test

  alias BB.Kino.JointControl
  alias BB.Kino.Test.JointRobot

  setup :configure_livebook_bridge

  setup do
    start_supervised!(JointRobot)
    :ok = BB.Safety.arm(JointRobot)
    :ok
  end

  test "a slider whose command is refused says so" do
    kino = JointControl.new(JointRobot)
    connect(kino)

    capture_log(fn ->
      push_event(kino, "set_position", %{"joint" => "shoulder", "position" => 0.5})

      assert_broadcast_event(kino, "command_error", %{message: message})
      assert message =~ "does not accept"
    end)
  end
end
