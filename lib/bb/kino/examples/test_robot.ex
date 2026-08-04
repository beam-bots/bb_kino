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
    use BB.Command

    alias BB.Message
    alias BB.Robot.Runtime, as: RobotRuntime

    @impl BB.Command
    def handle_command(goal, context, state) do
      joint_name = Map.get(goal, :joint, :shoulder_joint)
      duration_ms = Map.get(goal, :duration, 2000)
      steps = Map.get(goal, :steps, 20)

      robot = context.robot_module
      robot_struct = RobotRuntime.get_robot(robot)

      case Map.get(robot_struct.joints, joint_name) do
        nil ->
          {:stop, :normal, %{state | result: {:error, {:unknown_joint, joint_name}}}}

        joint ->
          lower = joint.limits[:lower] || -:math.pi()
          upper = joint.limits[:upper] || :math.pi()

          positions = RobotRuntime.configurations(robot)
          start_pos = Map.get(positions, joint_name, 0.0)

          step_delay = div(duration_ms, steps * 2)

          cycle_positions =
            interpolate(start_pos, lower, steps) ++
              interpolate(lower, upper, steps) ++
              interpolate(upper, start_pos, steps)

          state =
            Map.merge(state, %{
              robot: robot,
              joint_name: joint_name,
              remaining: cycle_positions,
              step_delay: step_delay
            })

          send(self(), :next_position)
          {:noreply, state}
      end
    end

    @impl BB.Command
    def handle_info(:next_position, state) do
      case state.remaining do
        [] ->
          {:stop, :normal, %{state | result: %{joint: state.joint_name, cycled: true}}}

        [pos | rest] ->
          publish_joint_position(state.robot, state.joint_name, pos)
          Process.send_after(self(), :next_position, state.step_delay)
          {:noreply, %{state | remaining: rest}}
      end
    end

    def handle_info(_msg, state), do: {:noreply, state}

    @impl BB.Command
    def result(%{result: {:error, _} = error}), do: error
    def result(%{result: result}), do: {:ok, result}

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
    use BB.Command

    alias BB.Robot.Runtime, as: RobotRuntime

    @impl BB.Command
    def handle_command(goal, context, state) do
      duration_ms = Map.get(goal, :duration, 1000)
      steps = Map.get(goal, :steps, 20)

      robot = context.robot_module
      robot_struct = RobotRuntime.get_robot(robot)
      positions = RobotRuntime.configurations(robot)

      step_delay = div(duration_ms, steps)
      joint_names = Map.keys(robot_struct.joints)

      state =
        Map.merge(state, %{
          robot: robot,
          joint_names: joint_names,
          start_positions: positions,
          current_step: 1,
          total_steps: steps,
          step_delay: step_delay
        })

      send(self(), :next_step)
      {:noreply, state}
    end

    @impl BB.Command
    def handle_info(:next_step, state) do
      if state.current_step > state.total_steps do
        {:stop, :normal, %{state | result: %{homed: true}}}
      else
        fraction = state.current_step / state.total_steps

        joint_positions =
          for joint_name <- state.joint_names do
            current = Map.get(state.start_positions, joint_name, 0.0)
            target = current * (1 - fraction)
            {joint_name, target}
          end

        publish_joint_positions(state.robot, joint_positions)
        Process.send_after(self(), :next_step, state.step_delay)
        {:noreply, %{state | current_step: state.current_step + 1}}
      end
    end

    def handle_info(_msg, state), do: {:noreply, state}

    @impl BB.Command
    def result(%{result: result}), do: {:ok, result}

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
    use BB.Command

    alias BB.Robot.Runtime, as: RobotRuntime

    @wave_shoulder :math.pi() / 4
    @wave_elbow :math.pi() / 2
    @wave_amplitude :math.pi() / 4

    @impl BB.Command
    def handle_command(goal, context, state) do
      cycles = Map.get(goal, :cycles, 3)
      speed = Map.get(goal, :speed, 1.0)

      robot = context.robot_module
      positions = RobotRuntime.configurations(robot)

      shoulder_start = Map.get(positions, :shoulder_joint, 0.0)
      elbow_start = Map.get(positions, :elbow_joint, 0.0)

      steps = round(20 / speed)
      step_delay = round(30 / speed)

      state =
        Map.merge(state, %{
          robot: robot,
          cycles: cycles,
          steps: steps,
          step_delay: step_delay,
          shoulder_start: shoulder_start,
          elbow_start: elbow_start,
          phase: :move_to_wave,
          current_step: 1,
          current_cycle: 1,
          wave_direction: :out
        })

      send(self(), :tick)
      {:noreply, state}
    end

    @impl BB.Command
    def handle_info(:tick, %{phase: :move_to_wave} = state) do
      if state.current_step > state.steps do
        Process.send_after(self(), :tick, state.step_delay)
        {:noreply, %{state | phase: :waving, current_step: 1}}
      else
        fraction = state.current_step / state.steps
        shoulder = state.shoulder_start + (@wave_shoulder - state.shoulder_start) * fraction
        elbow = state.elbow_start + (@wave_elbow - state.elbow_start) * fraction
        publish_positions(state.robot, shoulder, elbow)
        Process.send_after(self(), :tick, state.step_delay)
        {:noreply, %{state | current_step: state.current_step + 1}}
      end
    end

    def handle_info(:tick, %{phase: :waving} = state) do
      if state.current_step > state.steps do
        case {state.wave_direction, state.current_cycle} do
          {:out, _} ->
            Process.send_after(self(), :tick, state.step_delay)
            {:noreply, %{state | wave_direction: :back, current_step: 1}}

          {:back, cycle} when cycle >= state.cycles ->
            Process.send_after(self(), :tick, state.step_delay)
            {:noreply, %{state | phase: :return_home, current_step: 1}}

          {:back, cycle} ->
            Process.send_after(self(), :tick, state.step_delay)
            {:noreply, %{state | wave_direction: :out, current_step: 1, current_cycle: cycle + 1}}
        end
      else
        fraction = state.current_step / state.steps

        elbow =
          case state.wave_direction do
            :out -> @wave_elbow - @wave_amplitude * fraction
            :back -> @wave_elbow - @wave_amplitude + @wave_amplitude * fraction
          end

        publish_positions(state.robot, @wave_shoulder, elbow)
        Process.send_after(self(), :tick, state.step_delay)
        {:noreply, %{state | current_step: state.current_step + 1}}
      end
    end

    def handle_info(:tick, %{phase: :return_home} = state) do
      if state.current_step > state.steps do
        {:stop, :normal, %{state | result: %{waved: state.cycles}}}
      else
        fraction = state.current_step / state.steps
        shoulder = @wave_shoulder + (state.shoulder_start - @wave_shoulder) * fraction
        elbow = @wave_elbow + (state.elbow_start - @wave_elbow) * fraction
        publish_positions(state.robot, shoulder, elbow)
        Process.send_after(self(), :tick, state.step_delay)
        {:noreply, %{state | current_step: state.current_step + 1}}
      end
    end

    def handle_info(_msg, state), do: {:noreply, state}

    @impl BB.Command
    def result(%{result: result}), do: {:ok, result}

    defp publish_positions(robot, shoulder, elbow) do
      joint_names =
        robot
        |> RobotRuntime.get_robot()
        |> Map.get(:joints)
        |> Map.keys()

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
