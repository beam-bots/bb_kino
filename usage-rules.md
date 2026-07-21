<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# BB.Kino Usage Rules

`bb_kino` provides `BB.Kino`, a set of [Kino](https://hexdocs.pm/kino)
(Livebook) widgets for driving and monitoring a running [Beam Bots](https://hexdocs.pm/bb)
robot from inside a notebook cell. For BB framework basics, see `bb`'s rules
(`mix usage_rules.sync <file> bb:all`); this file covers only the widgets.

## Core principles

1. **These are Livebook widgets, not a DSL component.** `bb_kino` implements no
   `bb` behaviour, ships no DSL extension, and is never wired into a robot's
   `topology`. You call `BB.Kino.*` functions from a notebook cell; each returns
   a `Kino.JS.Live.t()` that Livebook renders as the cell result.
2. **The robot must already be running on the same node.** Every widget reads
   live runtime state (`BB.Robot.Runtime`, `BB.Safety`) and subscribes to the
   robot's PubSub. Start the robot's supervisor first — a widget built against a
   stopped robot has nothing to talk to.
3. **Pass the robot module, not a struct or a path.** Widgets take the robot
   module (e.g. `MyRobot`), the one that exports `robot/0`. They do not take a
   compiled `%BB.Robot{}` struct or a component path.

## Using it

Start the robot, then build a widget in its own cell:

```elixir
{:ok, _pid} = MyRobot.start_link()

BB.Kino.safety(MyRobot)
```

The available widgets, one per cell:

```elixir
BB.Kino.safety(MyRobot)         # arm/disarm controls + live state
BB.Kino.joints(MyRobot)         # position sliders per movable joint
BB.Kino.events(MyRobot)         # live stream of BB PubSub messages
BB.Kino.commands(MyRobot)       # tabbed forms to run the robot's commands
BB.Kino.visualisation(MyRobot)  # interactive 3D view, live joint updates
BB.Kino.parameters(MyRobot)     # view/edit robot parameters
```

Compose several into one dashboard with `Kino.Layout`:

```elixir
Kino.Layout.grid(
  [
    BB.Kino.safety(MyRobot),
    BB.Kino.joints(MyRobot),
    BB.Kino.visualisation(MyRobot)
  ],
  columns: 2
)
```

Or skip the code entirely: add the **Manage robot** Smart Cell (**+ Smart** in
Livebook), enter the robot module, and pick which widgets to show.

## Event stream options

`BB.Kino.events/2` is the only widget that takes options; all are optional:

```elixir
BB.Kino.events(MyRobot,
  path_filter: [:sensor],
  message_types: [BB.Message.Sensor.JointState]
)
```

| Option | Default | Meaning |
|---|---|---|
| `:path_filter` | `[]` (all) | List of path atoms to include, e.g. `[:sensor]` |
| `:message_types` | `[]` (all) | List of `BB.Message` type modules to include |
| `:max_messages` | `100` | Rows kept in the display buffer |
| `:flush_interval_ms` | `500` | How often buffered messages are rendered |
| `:debounce_window_ms` | `1000` | Window in which repeats of the same path + payload type are dropped |

## Anti-patterns

- **Don't declare it in the DSL.** There is no `BB.Kino` sensor/actuator/
  controller and nothing to supervise — never add it to `topology` or `use
  BB.Kino`. It is a cell-side rendering helper only.
- **Don't build a widget before the robot is started.** The module only has to
  export `robot/0` to pass validation, but the widget immediately queries
  runtime state and subscribes to PubSub — do `MyRobot.start_link()` first.
- **Don't expect output outside Livebook.** The return value is a live Kino
  widget; calling these from plain IEx or a script renders nothing useful.

## Further reading

- [bb_kino docs](https://hexdocs.pm/bb_kino) — including the
  [Interactive Control in Livebook](https://hexdocs.pm/bb_kino/01-interactive-control-in-livebook.html)
  tutorial
- [Kino](https://hexdocs.pm/kino) and [Livebook](https://livebook.dev/)
- `bb`'s rules (`mix usage_rules.sync <file> bb:all`)
