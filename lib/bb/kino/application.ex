# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Kino.SmartCell.register(BB.Kino.ManageRobotCell)

    children = []
    opts = [strategy: :one_for_one, name: BB.Kino.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
