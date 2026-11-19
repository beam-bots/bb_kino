<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Preview cameras in Livebook

`BB.Kino.camera/2` lists every camera a robot declares and previews the ones
that are running.

```elixir
{:ok, _pid} = MyRobot.start_link()

BB.Kino.camera(MyRobot, endpoint: "http://robot.local:4000/robot")
```

A camera is an ordinary `BB.Sensor` that also implements `BB.Camera`, declared
like any other sensor. Nothing has to be listed by hand.

## The endpoint, and why you have to supply it

Frames do not travel through Livebook. The widget sends names, statuses,
formats and a URL — nothing else — and each preview is an `<img>` in **your
browser** fetching MJPEG from a mounted `bb_liveview` dashboard.

So `:endpoint` is that dashboard's base URL *as your browser reaches it*, and
there is no sensible default:

* The Livebook **runtime** is often not the machine you're reading the notebook
  on — a Nerves device, a container, an attached remote node. `localhost` would
  mean your laptop, and would point at nothing.
* A dashboard bound to `127.0.0.1` on the robot is unreachable from your
  browser even when the runtime can see it. Bind it to a real interface.
* If Livebook is served over **HTTPS**, an `http://` stream is blocked as mixed
  content — usually with no visible error, just a preview that never loads.
  Serve the dashboard over HTTPS too, or open the notebook over HTTP.

You can supply it three ways:

```elixir
# per widget
BB.Kino.camera(MyRobot, endpoint: "http://robot.local:4000/robot")

# once, for the notebook
Application.put_env(:bb_kino, :dashboard_url, "http://robot.local:4000/robot")
BB.Kino.camera(MyRobot)
```

…or leave it out entirely and paste it into the widget's own **Dashboard URL**
field. Discovery works without it: the cameras are listed, each with its state,
and only the pictures are missing.

## What you need running

The preview comes from `bb_liveview`, so the robot's host application must
mount a dashboard:

```elixir
scope "/" do
  pipe_through :browser
  bb_dashboard "/robot", robot: MyRobot
end
```

The endpoint is then whatever path that mount is at —
`http://robot.local:4000/robot` above. The camera route lives inside the same
scope, so it is protected by whatever pipeline protects the dashboard, and by
nothing else: if the dashboard is public, the stream is public.

`bb_kino` does not depend on `bb_liveview`, and does not serve HTTP itself.
Streaming straight from Livebook would mean a second HTTP server with its own
authentication story; pointing at the dashboard you already have is the honest
version.

## Trying it without hardware

`bb_liveview`'s dev server runs a synthetic camera — real JPEG frames, no
hardware — and serves it on port 4000:

```sh
cd bb_liveview
mix deps.get
mix assets.setup && mix assets.build
mix phx.server
```

Then in a notebook on the same machine:

```elixir
BB.Kino.camera(Dev.TestRobot, endpoint: "http://localhost:4000")
```

`localhost` is correct *here* only because the browser, Livebook and the dev
server are all on the same machine. Nowhere else.

## What the states mean

| Status | Meaning |
|---|---|
| `capturing` | The hub is alive and the driver is producing frames |
| `running` | The hub is alive; nobody is consuming, so capture is stopped |
| `declared` | In the robot's DSL, but not alive — robot stopped, sensor crashed, or hardware missing |

A `declared` camera is shown rather than hidden on purpose: "this robot has no
camera" and "this robot's camera is broken" should not look the same.

Pausing a preview removes the `<img>`, which closes the HTTP connection and
drops the consumer. The camera stops capturing once the last consumer goes.
