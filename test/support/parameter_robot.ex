# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Test.ParameterRobot do
  @moduledoc """
  A robot whose parameters cover each type the parameters widget can render,
  including unit-typed parameters with and without bounds.
  """
  use BB

  settings do
    name(:parameter_robot)
  end

  parameters do
    group :motion do
      param(:gain, type: :float, default: 0.5, min: 0.0, max: 1.0)

      param(:trim,
        type: {:unit, :degree},
        default: ~u(0 degree),
        min: ~u(-30 degree),
        max: ~u(30 degree)
      )

      param(:reach, type: {:unit, :meter}, default: ~u(0.5 meter))
    end
  end

  topology do
    link :base_link do
    end
  end
end
