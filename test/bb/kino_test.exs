# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.KinoTest do
  use ExUnit.Case
  doctest BB.Kino

  test "greets the world" do
    assert BB.Kino.hello() == :world
  end
end
