<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# Beam Bots Kino Livebook integration

[![CI](https://github.com/beam-bots/bb_kino/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_kino/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Hex version badge](https://img.shields.io/hexpm/v/bb_kino.svg)](https://hex.pm/packages/bb_kino)
[![REUSE status](https://api.reuse.software/badge/github.com/beam-bots/bb_kino)](https://api.reuse.software/info/github.com/beam-bots/bb_kino)

# BB.Servo.PCA9685

BB integration for driving RC servos via PCA9685 16-channel PWM controller over I2C.

This library provides a controller and actuator module for controlling RC servos
connected to a PCA9685 board.

## Installation

Add `bb_kino` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bb_kino, "~> 0.1.0"}
  ]
end
```

## Requirements

- BB framework (`~> 0.4`)

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/bb_kino).
