<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to Create Combined Widget Layouts

Arrange BB Kino widgets in custom layouts for different use cases.

## Prerequisites

- Completed [Interactive Control in Livebook](../tutorials/01-interactive-control-in-livebook.md)
- Robot started in Livebook

## Using Kino.Layout

BB Kino widgets are standard Kino outputs. Combine them with `Kino.Layout.grid/2`:

```elixir
Kino.Layout.grid([
  BB.Kino.safety(MyRobot),
  BB.Kino.joints(MyRobot),
  BB.Kino.visualisation(MyRobot)
], columns: 3)
```

## Common Layout Patterns

### Control Panel (Left) + Visualisation (Right)

```elixir
Kino.Layout.grid([
  Kino.Layout.grid([
    BB.Kino.safety(MyRobot),
    BB.Kino.joints(MyRobot),
    BB.Kino.commands(MyRobot)
  ], columns: 1),
  BB.Kino.visualisation(MyRobot)
], columns: 2)
```

### Full Dashboard

```elixir
Kino.Layout.grid([
  # Top row: safety and joints
  Kino.Layout.grid([
    BB.Kino.safety(MyRobot),
    BB.Kino.joints(MyRobot)
  ], columns: 2),

  # Middle row: visualisation and events
  Kino.Layout.grid([
    BB.Kino.visualisation(MyRobot),
    BB.Kino.events(MyRobot)
  ], columns: 2),

  # Bottom row: commands
  BB.Kino.commands(MyRobot)
], columns: 1)
```

### Monitoring Only (No Control)

```elixir
Kino.Layout.grid([
  BB.Kino.visualisation(MyRobot),
  BB.Kino.events(MyRobot)
], columns: 2)
```

### Minimal Control

```elixir
Kino.Layout.grid([
  BB.Kino.safety(MyRobot),
  BB.Kino.joints(MyRobot)
], columns: 1)
```

## Nested Layouts

Create complex arrangements with nested grids:

```elixir
left_panel = Kino.Layout.grid([
  BB.Kino.safety(MyRobot),
  BB.Kino.joints(MyRobot)
], columns: 1)

right_panel = Kino.Layout.grid([
  BB.Kino.visualisation(MyRobot),
  BB.Kino.events(MyRobot)
], columns: 1)

Kino.Layout.grid([left_panel, right_panel], columns: 2)
```

## Adding Labels

Use `Kino.Markdown` for section headers:

```elixir
Kino.Layout.grid([
  Kino.Markdown.new("## Control"),
  BB.Kino.safety(MyRobot),
  BB.Kino.joints(MyRobot),
  Kino.Markdown.new("## Monitoring"),
  BB.Kino.events(MyRobot)
], columns: 1)
```

## Conditional Widgets

Show different widgets based on conditions:

```elixir
widgets = [BB.Kino.safety(MyRobot)]

widgets =
  if has_joints?(MyRobot) do
    widgets ++ [BB.Kino.joints(MyRobot)]
  else
    widgets
  end

widgets =
  if has_commands?(MyRobot) do
    widgets ++ [BB.Kino.commands(MyRobot)]
  else
    widgets
  end

Kino.Layout.grid(widgets, columns: 1)
```

## Using Tabs

Organise widgets in tabs with `Kino.Layout.tabs/1`:

```elixir
Kino.Layout.tabs([
  Control: Kino.Layout.grid([
    BB.Kino.safety(MyRobot),
    BB.Kino.joints(MyRobot)
  ], columns: 1),
  Visualisation: BB.Kino.visualisation(MyRobot),
  Events: BB.Kino.events(MyRobot),
  Commands: BB.Kino.commands(MyRobot)
])
```

## Multiple Robots

Control multiple robots in one notebook:

```elixir
Kino.Layout.grid([
  Kino.Markdown.new("## Robot 1"),
  Kino.Layout.grid([
    BB.Kino.safety(Robot1),
    BB.Kino.joints(Robot1)
  ], columns: 2),

  Kino.Markdown.new("## Robot 2"),
  Kino.Layout.grid([
    BB.Kino.safety(Robot2),
    BB.Kino.joints(Robot2)
  ], columns: 2)
], columns: 1)
```

## Responsive Considerations

Livebook cells have a fixed width. For complex layouts:

- Use 2-3 columns maximum
- Place controls on the left
- Put visualisation in a wider column
- Test at different zoom levels

## Performance Tips

- Events widget can be resource-intensive with high message rates - add path filters
- Visualisation updates are throttled by default
- For many joints, consider a more compact layout

## Saving Layouts as Functions

Create reusable layout functions:

```elixir
defmodule MyLayouts do
  def control_panel(robot) do
    Kino.Layout.grid([
      BB.Kino.safety(robot),
      BB.Kino.joints(robot)
    ], columns: 1)
  end

  def full_dashboard(robot) do
    Kino.Layout.grid([
      control_panel(robot),
      Kino.Layout.grid([
        BB.Kino.visualisation(robot),
        BB.Kino.events(robot)
      ], columns: 1)
    ], columns: 2)
  end
end

MyLayouts.full_dashboard(MyRobot)
```
