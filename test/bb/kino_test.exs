# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.KinoTest do
  use ExUnit.Case
  doctest BB.Kino

  describe "module structure" do
    test "exports safety/1" do
      assert function_exported?(BB.Kino, :safety, 1)
    end

    test "exports joints/1" do
      assert function_exported?(BB.Kino, :joints, 1)
    end

    test "exports events/1" do
      assert function_exported?(BB.Kino, :events, 1)
    end

    test "exports events/2" do
      assert function_exported?(BB.Kino, :events, 2)
    end

    test "exports commands/1" do
      assert function_exported?(BB.Kino, :commands, 1)
    end

    test "exports visualisation/1" do
      assert function_exported?(BB.Kino, :visualisation, 1)
    end
  end
end
