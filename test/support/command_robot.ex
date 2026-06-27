# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Test.RunForever do
  @moduledoc """
  A command that never completes on its own — it stays running until cancelled.

  Used to exercise the widget's handling of long-running/continuous commands.
  """
  use BB.Command

  @impl BB.Command
  def handle_command(_goal, _context, state), do: {:noreply, state}

  @impl BB.Command
  def result(%{result: nil}), do: {:error, :cancelled}
  def result(%{result: result}), do: result
end

defmodule BB.Kino.Test.CommandRobot do
  @moduledoc """
  A minimal robot exposing a single continuous command, for widget tests.
  """
  use BB

  settings do
    name(:kino_command_robot)
  end

  commands do
    command :run_forever do
      handler(BB.Kino.Test.RunForever)
      allowed_states([:disarmed])
    end
  end

  topology do
    link :base_link do
    end
  end
end
