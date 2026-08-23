# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Test.PlanarRobot do
  @moduledoc """
  A robot whose chain starts at a planar joint, for exercising the widgets'
  handling of configurations that aren't a single float.

  A planar joint's configuration is a `BB.Math.Transform2D` and a floating
  joint's a `BB.Math.Transform`, neither of which the browser can be handed
  directly.
  """
  use BB

  settings do
    name(:kino_planar_robot)
  end

  topology do
    link :world do
      joint :ground do
        type(:planar)

        axis do
        end

        link :base_link do
          joint :shoulder do
            type(:revolute)

            limit do
              lower(~u(-90 degree))
              upper(~u(90 degree))
              effort(~u(10 newton_meter))
              velocity(~u(180 degree_per_second))
            end

            link(:arm_link)
          end
        end
      end
    end
  end
end
