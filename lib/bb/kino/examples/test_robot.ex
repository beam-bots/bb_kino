# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Kino.Examples.TestRobot do
  @moduledoc """
  An example robot for testing BB.Kino widgets.

  This robot has a simple 2-joint arm topology with commands for:
  - Arming/disarming
  - Cycling joints through their range of motion
  - Moving to home position

  ## Usage in Livebook

      {:ok, _pid} = BB.Kino.Examples.TestRobot.start_link()

      # Create the management widget
      BB.Kino.safety(BB.Kino.Examples.TestRobot)
  """
  use BB
  import BB.Unit

  # Command handler for cycling a joint through its range
  defmodule CycleJoint do
    @moduledoc false
    @behaviour BB.Command

    alias BB.Message
    alias BB.Robot.Runtime, as: RobotRuntime

    @impl true
    def handle_command(goal, context) do
      joint_name = Map.get(goal, :joint, :shoulder_joint)
      duration_ms = Map.get(goal, :duration, 2000)
      steps = Map.get(goal, :steps, 20)

      robot = context.robot_module
      robot_struct = RobotRuntime.get_robot(robot)

      case Map.get(robot_struct.joints, joint_name) do
        nil ->
          {:error, {:unknown_joint, joint_name}}

        joint ->
          lower = joint.limits[:lower] || -:math.pi()
          upper = joint.limits[:upper] || :math.pi()

          # Get current position
          positions = RobotRuntime.positions(robot)
          start_pos = Map.get(positions, joint_name, 0.0)

          step_delay = div(duration_ms, steps * 2)

          # Cycle: start -> lower -> upper -> start
          cycle_positions =
            interpolate(start_pos, lower, steps) ++
              interpolate(lower, upper, steps) ++
              interpolate(upper, start_pos, steps)

          for pos <- cycle_positions do
            publish_joint_position(robot, joint_name, pos)
            Process.sleep(step_delay)
          end

          {:ok, %{joint: joint_name, cycled: true}}
      end
    end

    defp interpolate(from, to, steps) do
      step_size = (to - from) / steps

      for i <- 1..steps do
        from + step_size * i
      end
    end

    defp publish_joint_position(robot, joint_name, position) do
      {:ok, msg} =
        Message.new(BB.Message.Sensor.JointState, :simulated,
          names: [joint_name],
          positions: [position * 1.0],
          velocities: [0.0],
          efforts: [0.0]
        )

      BB.publish(robot, [:sensor, :simulated], msg)
    end
  end

  # Command handler for moving to home position
  defmodule GoHome do
    @moduledoc false
    @behaviour BB.Command

    alias BB.Message
    alias BB.Robot.Runtime, as: RobotRuntime

    @impl true
    def handle_command(goal, context) do
      duration_ms = Map.get(goal, :duration, 1000)
      steps = Map.get(goal, :steps, 20)

      robot = context.robot_module
      robot_struct = RobotRuntime.get_robot(robot)
      positions = RobotRuntime.positions(robot)

      step_delay = div(duration_ms, steps)

      # Move all joints to 0
      joint_names = Map.keys(robot_struct.joints)

      for i <- 1..steps do
        fraction = i / steps

        joint_positions =
          for joint_name <- joint_names do
            current = Map.get(positions, joint_name, 0.0)
            target = current * (1 - fraction)
            {joint_name, target}
          end

        publish_joint_positions(robot, joint_positions)
        Process.sleep(step_delay)
      end

      {:ok, %{homed: true}}
    end

    defp publish_joint_positions(robot, joint_positions) do
      {names, positions} = Enum.unzip(joint_positions)

      {:ok, msg} =
        BB.Message.new(BB.Message.Sensor.JointState, :simulated,
          names: names,
          positions: positions,
          velocities: List.duplicate(0.0, length(names)),
          efforts: List.duplicate(0.0, length(names))
        )

      BB.publish(robot, [:sensor, :simulated], msg)
    end
  end

  # Command handler for waving (demo animation)
  defmodule Wave do
    @moduledoc false
    @behaviour BB.Command

    alias BB.Message
    alias BB.Robot.Runtime, as: RobotRuntime

    @impl true
    def handle_command(goal, context) do
      cycles = Map.get(goal, :cycles, 3)
      speed = Map.get(goal, :speed, 1.0)

      robot = context.robot_module
      positions = RobotRuntime.positions(robot)

      # Save starting positions
      shoulder_start = Map.get(positions, :shoulder_joint, 0.0)
      elbow_start = Map.get(positions, :elbow_joint, 0.0)

      # First, move shoulder up and elbow bent
      wave_shoulder = :math.pi() / 4
      wave_elbow = :math.pi() / 2

      steps = round(20 / speed)
      step_delay = round(30 / speed)

      # Move to wave position
      for i <- 1..steps do
        fraction = i / steps
        shoulder = shoulder_start + (wave_shoulder - shoulder_start) * fraction
        elbow = elbow_start + (wave_elbow - elbow_start) * fraction
        publish_positions(robot, shoulder, elbow)
        Process.sleep(step_delay)
      end

      # Wave back and forth
      for _cycle <- 1..cycles do
        # Wave one way (elbow extends)
        for i <- 1..steps do
          fraction = i / steps
          elbow = wave_elbow - :math.pi() / 4 * fraction
          publish_positions(robot, wave_shoulder, elbow)
          Process.sleep(step_delay)
        end

        # Wave back (elbow bends)
        for i <- 1..steps do
          fraction = i / steps
          elbow = wave_elbow - :math.pi() / 4 + :math.pi() / 4 * fraction
          publish_positions(robot, wave_shoulder, elbow)
          Process.sleep(step_delay)
        end
      end

      # Return to start
      for i <- 1..steps do
        fraction = i / steps
        shoulder = wave_shoulder + (shoulder_start - wave_shoulder) * fraction
        elbow = wave_elbow + (elbow_start - wave_elbow) * fraction
        publish_positions(robot, shoulder, elbow)
        Process.sleep(step_delay)
      end

      {:ok, %{waved: cycles}}
    end

    defp publish_positions(robot, shoulder, elbow) do
      joint_names =
        robot
        |> RobotRuntime.get_robot()
        |> Map.get(:joints)
        |> Map.keys()

      # Only publish for joints that exist
      {names, positions} =
        [{:shoulder_joint, shoulder}, {:elbow_joint, elbow}]
        |> Enum.filter(fn {name, _} -> name in joint_names end)
        |> Enum.unzip()

      unless Enum.empty?(names) do
        count = length(names)

        {:ok, msg} =
          BB.Message.new(BB.Message.Sensor.JointState, :simulated,
            names: names,
            positions: positions,
            velocities: List.duplicate(0.0, count),
            efforts: List.duplicate(0.0, count)
          )

        BB.publish(robot, [:sensor, :simulated], msg)
      end
    end
  end

  settings do
    name(:bb_kino_test_robot)
  end

  commands do
    command :arm do
      handler(BB.Command.Arm)
      allowed_states([:disarmed])
    end

    command :disarm do
      handler(BB.Command.Disarm)
      allowed_states([:idle])
    end

    command :cycle_joint do
      handler(CycleJoint)
      allowed_states([:idle])

      argument :joint, :atom do
        required(false)
        default(:shoulder_joint)
        doc("Joint to cycle (shoulder_joint or elbow_joint)")
      end

      argument :duration, :integer do
        required(false)
        default(2000)
        doc("Duration in milliseconds")
      end
    end

    command :go_home do
      handler(GoHome)
      allowed_states([:idle])

      argument :duration, :integer do
        required(false)
        default(1000)
        doc("Duration in milliseconds")
      end
    end

    command :wave do
      handler(Wave)
      allowed_states([:idle])

      argument :cycles, :integer do
        required(false)
        default(3)
        doc("Number of wave cycles")
      end

      argument :speed, :float do
        required(false)
        default(1.0)
        doc("Speed multiplier (0.5 = half speed, 2.0 = double speed)")
      end
    end
  end

  topology do
    link :base_link do
      visual do
        cylinder do
          radius(~u(0.05 meter))
          height(~u(0.1 meter))
        end
      end

      joint :shoulder_joint do
        type(:revolute)

        origin do
          z(~u(0.1 meter))
        end

        limit do
          lower(~u(-180 degree))
          upper(~u(180 degree))
          effort(~u(10 newton_meter))
          velocity(~u(90 degree_per_second))
        end

        link :upper_arm do
          visual do
            origin do
              z(~u(0.15 meter))
            end

            cylinder do
              radius(~u(0.04 meter))
              height(~u(0.3 meter))
            end
          end

          joint :elbow_joint do
            type(:revolute)

            origin do
              z(~u(0.3 meter))
            end

            axis do
              roll(~u(-90 degree))
            end

            limit do
              lower(~u(0 degree))
              upper(~u(180 degree))
              effort(~u(10 newton_meter))
              velocity(~u(90 degree_per_second))
            end

            link :forearm do
              visual do
                origin do
                  z(~u(0.125 meter))
                end

                cylinder do
                  radius(~u(0.03 meter))
                  height(~u(0.25 meter))
                end
              end
            end
          end
        end
      end
    end
  end
end
