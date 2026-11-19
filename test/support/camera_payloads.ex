# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Message.Camera.BeginCapture do
  @moduledoc """
  A stand-in for the payload `bb_camera` publishes when a camera starts
  capturing.

  `bb_camera` is not a dependency of `bb_kino` — the widget refreshes its list
  when it sees one of those payloads, identified by module name, and this is
  the smallest thing that is one. The real struct carries more.
  """

  defstruct [:stream_info, :subscriber_count]
end
