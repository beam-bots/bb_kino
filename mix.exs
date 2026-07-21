# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Servo.Kino.MixProject do
  use Mix.Project

  @moduledoc """
  Beam Bots integration for Kino widgets in LiveBook.
  """

  @version "0.3.7"

  def project do
    [
      aliases: aliases(),
      app: :bb_kino,
      consolidate_protocols: Mix.env() == :prod,
      deps: deps(),
      description: @moduledoc,
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  defp dialyzer, do: []

  defp package do
    [
      maintainers: ["James Harton <james@harton.nz>"],
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => "https://github.com/beam-bots/bb_kino",
        "Sponsor" => "https://github.com/sponsors/jimsynz"
      },
      files: ~w(lib priv/static .formatter.exs mix.exs README* LICENSE* CHANGELOG* usage-rules.md)
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BB.Kino.Application, []}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      extras:
        ["README.md", "CHANGELOG.md"]
        |> Enum.concat(Path.wildcard("documentation/**/*.{md,livemd,cheatmd}")),
      groups_for_extras: [
        Tutorials: ~r/tutorials\//,
        "How-to Guides": ~r/how-to\//
      ],
      source_ref: "main",
      source_url: "https://github.com/beam-bots/bb_kino"
    ]
  end

  defp aliases do
    [
      "assets.setup": ["cmd --cd assets/visualisation npm install"],
      "assets.build": ["cmd --cd assets/visualisation npm run build"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bb, bb_dep("~> 0.16")},
      {:kino, "~> 0.18"},

      # dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.2", only: :test, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp bb_dep(default) do
    case System.get_env("BB_VERSION") do
      nil -> default
      "local" -> [path: "../bb", override: true]
      "main" -> [git: "https://github.com/beam-bots/bb.git", override: true]
      version -> "~> #{version}"
    end
  end
end
